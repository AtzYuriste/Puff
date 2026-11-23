# Group notes

Group: g974 · Members: Jason QIU, Yannick ZHENG, Zhiqiang FANG, Mélodie VUONG · App: <https://github.com/traefik/whoami.git>

Write every decision here with one line of why. It becomes your defense pitch.

## M0, setup + IAM

- check output:

```
PASS M0 Floci reachable
PASS M0 one IAM user per member (found 5)
PASS M0 read-only auditor user exists
PASS M0 auditor denied proof saved in NOTES.md
PASS M0 group bucket exists
```

- AccessDenied proof:
  - : [ERROR]: An error occurred (AccessDenied) when calling the CreateBucket operation: User is not authorized to perform: s3:CreateBucket

## M1, compute + data

- check output:

```
PASS M1 app image in ECR
PASS M1 ECS service running (1 task)
PASS M1 ALB answers 200
PASS M1 RDS Postgres available
PASS M1 S3 status page online
PASS M1 infra/deploy.sh committed
```

## M2, Network

- check output:

```
PASS M2 VPC g974-vpc exists
PASS M2 2 public subnets (route to IGW)
PASS M2 2 private subnets (route to NAT)
PASS M2 ALB in the public subnets
PASS M2 ALB answers 200
PASS M2 app service in the private subnets
PASS M2 app tasks without public IP
PASS M2 app security group not open to 0.0.0.0/0
PASS M2 database in the VPC, not public
PASS M2 database only reachable from the app's group
PASS M2 intruder blocked from the app
PASS M2 naive deploy deleted (no public DB, no service outside the VPC)
```

## M3, Logs and secrets

SQS Notification Message from Cloudwatch :

```
{"Type":"Notification","MessageId":"f0128bfa-3e5f-48ec-bb3b-e12d64b29009","TopicArn":"arn:aws:sns:us-east-1:000000000000:g974-alerts","Timestamp":"2026-11-23T11:54:08.706Z","Subject":"ALARM: \"g974-errors\"","Message":"{\"AlarmName\":\"g974-errors\",\"AlarmDescription\":null,\"AWSAccountId\":\"000000000000\",\"AlarmConfigurationUpdatedTimestamp\":\"2026-11-23T11:53:28.000+0000\",\"NewStateValue\":\"ALARM\",\"NewStateReason\":\"Threshold Crossed: 1 datapoint(s) breaching the threshold.\",\"StateChangeTime\":\"2026-11-23T11:54:08.000+0000\",\"Region\":\"US East (N. Virginia)\",\"AlarmArn\":\"arn:aws:cloudwatch:us-east-1:000000000000:alarm:g974-errors\",\"OldStateValue\":\"INSUFFICIENT_DATA\",\"OKActions\":[],\"AlarmActions\":[\"arn:aws:sns:us-east-1:000000000000:g974-alerts\"],\"InsufficientDataActions\":[],\"Trigger\":{\"MetricName\":\"Errors\",\"Namespace\":\"g974\",\"StatisticType\":\"Statistic\",\"Statistic\":\"SUM\",\"Unit\":null,\"Dimensions\":[],\"Period\":60,\"EvaluationPeriods\":1,\"ComparisonOperator\":\"GreaterThanOrEqualToThreshold\",\"Threshold\":1.0,\"TreatMissingData\":null,\"EvaluateLowSampleCountPercentile\":\"\"}}","SignatureVersion":"1","Signature":"cX91tyK9MOsP0arQ3CM5aUOm05iWorDXflLkoKHUtA6Qi8HMGp0H/tp8SG4t4Lte86+CVtvFhejlNLgDd6yNTOS8HYGr83frFqwWsHhsf2wPsE4ynfS66eSXvlMSe0rN+tk0VsVQIgVSWZme+ZlxPRxvTV1uORTzdYswsJbsgnL/Jf0X8VfhIATFBviP8fnlUP1xeqvdg7BX1HA68ic0xUA5zo92pO4i+815czLAjDUno0cTEkZg+yBWrxeHLrd3oBzoBQ5TeGc7kt/5IQDRit5FNPWBjKZGK3IncMnB+7b56nIg+01oHo9ZGiDoF2DLzQFVNyIkaRn20Gw+2M6MFg==","SigningCertURL":"http://localhost:4566/_aws/sns/SimpleNotificationService-00221c697eb0eb3872db2b29d6075339.pem","UnsubscribeURL":"http://localhost:4566/?Action=Unsubscribe&SubscriptionArn=arn:aws:sns:us-east-1:000000000000:g974-alerts:7f009b0b-e35a-46af-831e-ff3c9fd05b2b","MessageAttributes":{}}
```

## deployer proof

```
aws rds delete-db-instance --db-instance-identifier $GROUP-db2 --skip-final-snapshot 2>&1
```

Output :

```
aws: [ERROR]: An error occurred (AccessDenied) when calling the DeleteDBInstance operation: User is not authorized to perform: rds:DeleteDBInstance
```
