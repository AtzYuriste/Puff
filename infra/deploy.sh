#!/bin/bash
# Your group's deploy script. Put every command you run here, in order,
# so any member can rebuild your infra from zero on their machine.
set -e
cd "$(dirname "$0")/.." && . ./env.sh
: "${GROUP:?export GROUP=gXX first}"

# M0: IAM
for u in jason yannick zhiqiang melodie; do
  aws iam create-user --user-name $GROUP-$u
done
aws iam create-group --group-name $GROUP-admins
aws iam attach-group-policy --group-name $GROUP-admins \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
for u in jason yannick zhiqiang melodie; do
  aws iam add-user-to-group --group-name $GROUP-admins --user-name $GROUP-$u
done

aws iam create-user --user-name $GROUP-auditor
aws iam put-user-policy --user-name $GROUP-auditor --policy-name read-only \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:List*","s3:Get*","ec2:Describe*"],"Resource":"*"}]}'

# M0: bucket
aws s3api create-bucket --bucket $GROUP-site

# M1
# Step 1
aws ecr create-repository --repository-name $GROUP-app
git clone --depth 1 https://github.com/traefik/whoami.git app-src
docker build -t $REGISTRY/$GROUP-app:v1 app-src
docker push $REGISTRY/$GROUP-app:v1
aws ecr list-images --repository-name $GROUP-app

# Step 2
VPC=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' --output text)

SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC \
  --query 'Subnets[:2].SubnetId' --output text | tr '\t' ',')

ALB_SG=$(aws ec2 create-security-group --group-name $GROUP-alb-sg \
  --description "ALB" --vpc-id $VPC --query GroupId --output text)
APP_SG=$(aws ec2 create-security-group --group-name $GROUP-app-sg \
  --description "app" --vpc-id $VPC --query GroupId --output text)

aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $APP_SG --protocol tcp --port 80 --cidr 0.0.0.0/0

# Step 3
ALB=$(aws elbv2 create-load-balancer --name $GROUP-alb \
  --subnets ${SUBNETS//,/ } --security-groups $ALB_SG \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

TG=$(aws elbv2 create-target-group --name $GROUP-tg \
  --protocol HTTP --port 80 --target-type ip --vpc-id $VPC --health-check-path / \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

aws elbv2 create-listener --load-balancer-arn $ALB --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG

# Step 4
aws ecs create-cluster --cluster-name $GROUP

aws ecs register-task-definition --family $GROUP-app \
  --network-mode awsvpc --requires-compatibilities FARGATE --cpu 256 --memory 512 \
  --container-definitions "[{\"name\":\"app\",\"image\":\"$REGISTRY/$GROUP-app:v1\",\"portMappings\":[{\"containerPort\":80}],\"essential\":true}]"

aws ecs create-service --cluster $GROUP --service-name $GROUP-app \
  --task-definition $GROUP-app --desired-count 1 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$APP_SG],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=$TG,containerName=app,containerPort=80"

# Step 5

aws rds create-db-instance --db-instance-identifier $GROUP-db \
  --engine postgres --db-instance-class db.t3.micro --allocated-storage 20 \
  --master-username app --master-user-password 'ChangeMe-123' \
  --publicly-accessible

aws rds describe-db-instances --db-instance-identifier $GROUP-db \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address,Endpoint.Port]'

# Step 6

echo "<h1>$GROUP is up</h1>" > index.html
aws s3 cp index.html s3://$GROUP-site/

aws s3 website s3://$GROUP-site/ --index-document index.html

aws s3api delete-public-access-block --bucket $GROUP-site

aws s3api put-bucket-policy --bucket $GROUP-site --policy "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::$GROUP-site/*\"}]}"

# M2

# Step 1

# Your private network, 65,536 addresses, tagged with your group name
VPC2=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$GROUP-vpc}]" \
  --query Vpc.VpcId --output text)

# Two public subnets, one per AZ
PUB_A=$(aws ec2 create-subnet --vpc-id $VPC2 --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a --query Subnet.SubnetId --output text)
PUB_B=$(aws ec2 create-subnet --vpc-id $VPC2 --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b --query Subnet.SubnetId --output text)

# Two private subnets, one per AZ
PRIV_A=$(aws ec2 create-subnet --vpc-id $VPC2 --cidr-block 10.0.11.0/24 \
  --availability-zone us-east-1a --query Subnet.SubnetId --output text)
PRIV_B=$(aws ec2 create-subnet --vpc-id $VPC2 --cidr-block 10.0.12.0/24 \
  --availability-zone us-east-1b --query Subnet.SubnetId --output text)

# Step 2

# The internet gateway: the two-way door, attached to the VPC
IGW=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC2

# Public route table: "everything else goes to the internet gateway"
PUB_RT=$(aws ec2 create-route-table --vpc-id $VPC2 --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id $PUB_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW

# Attach it to the two public subnets
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB_A
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB_B

# The NAT gateway: the one-way exit, it lives in a public subnet with a fixed public IP
EIP=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
NAT=$(aws ec2 create-nat-gateway --subnet-id $PUB_A --allocation-id $EIP \
  --query NatGateway.NatGatewayId --output text)

# Private route table: "everything else goes out through the NAT", nothing comes in
PRIV_RT=$(aws ec2 create-route-table --vpc-id $VPC2 --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id $PRIV_RT --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT

# Attach it to the two private subnets
aws ec2 associate-route-table --route-table-id $PRIV_RT --subnet-id $PRIV_A
aws ec2 associate-route-table --route-table-id $PRIV_RT --subnet-id $PRIV_B

# Step 3

# Three firewalls, one per layer
ALB_SG2=$(aws ec2 create-security-group --group-name $GROUP-alb-sg2 \
  --description "ALB, public" --vpc-id $VPC2 --query GroupId --output text)
APP_SG2=$(aws ec2 create-security-group --group-name $GROUP-app-sg2 \
  --description "app, only from the ALB" --vpc-id $VPC2 --query GroupId --output text)
DB_SG2=$(aws ec2 create-security-group --group-name $GROUP-db-sg2 \
  --description "db, only from the app" --vpc-id $VPC2 --query GroupId --output text)

# The ALB accepts the whole internet on port 80
aws ec2 authorize-security-group-ingress --group-id $ALB_SG2 --protocol tcp --port 80 --cidr 0.0.0.0/0

# The app accepts port 80 from the load balancer's network only (see the note below)
aws ec2 authorize-security-group-ingress --group-id $APP_SG2 --protocol tcp --port 80 --cidr 172.17.0.0/16

# The database accepts 5432 from the app's security group only
aws ec2 authorize-security-group-ingress --group-id $DB_SG2 --protocol tcp --port 5432 --source-group $APP_SG2

# Step 4

# The ALB, in the two public subnets
ALB2=$(aws elbv2 create-load-balancer --name $GROUP-alb2 \
  --subnets $PUB_A $PUB_B --security-groups $ALB_SG2 \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Its target group, in the new VPC
TG2=$(aws elbv2 create-target-group --name $GROUP-tg2 \
  --protocol HTTP --port 80 --target-type ip --vpc-id $VPC2 --health-check-path / \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# Its listener
aws elbv2 create-listener --load-balancer-arn $ALB2 --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG2

# Step 5

# The v2 service: private subnets, app firewall, no public IP
aws ecs create-service --cluster $GROUP --service-name $GROUP-app2 \
  --task-definition $GROUP-app --desired-count 1 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$PRIV_A,$PRIV_B],securityGroups=[$APP_SG2],assignPublicIp=DISABLED}" \
  --load-balancers "targetGroupArn=$TG2,containerName=app,containerPort=80"

# Step 6 

# Tell RDS which subnets it may use: the private ones
aws rds create-db-subnet-group --db-subnet-group-name $GROUP-db-subnets \
  --db-subnet-group-description "private subnets" --subnet-ids $PRIV_A $PRIV_B

# The v2 database: private subnets, database firewall, not public
aws rds create-db-instance --db-instance-identifier $GROUP-db2 \
  --engine postgres --db-instance-class db.t3.micro --allocated-storage 20 \
  --master-username app --master-user-password 'ChangeMe-123' \
  --db-subnet-group-name $GROUP-db-subnets --vpc-security-group-ids $DB_SG2 \
  --no-publicly-accessible

# Step 8

# Stop and delete the M1 service
aws ecs update-service --cluster $GROUP --service $GROUP-app --desired-count 0
aws ecs delete-service --cluster $GROUP --service $GROUP-app

# Delete the M1 load balancer and its target group
aws elbv2 delete-load-balancer --load-balancer-arn $(aws elbv2 describe-load-balancers \
  --names $GROUP-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text)
aws elbv2 delete-target-group --target-group-arn $(aws elbv2 describe-target-groups \
  --names $GROUP-tg --query 'TargetGroups[0].TargetGroupArn' --output text)

# Delete the public database
aws rds delete-db-instance --db-instance-identifier $GROUP-db --skip-final-snapshot