# Group notes

Group: g974 · Members: Jason QIU, Yannick ZHENG, Zhiqiang FANG, Mélodie VUONG · App: <https://github.com/AtzYuriste/Puff.git>

Write every decision here with one line of why. It becomes your defense pitch.

## M0, setup + IAM

- check output:
  - PASS M0 Floci reachable
    PASS M0 one IAM user per member (found 5)
    PASS M0 read-only auditor user exists
    PASS M0 auditor denied proof saved in NOTES.md
    PASS M0 group bucket exists
- AccessDenied proof:
  - : [ERROR]: An error occurred (AccessDenied) when calling the CreateBucket operation: User is not authorized to perform: s3:CreateBucket

## M1, compute + data

- check output:
