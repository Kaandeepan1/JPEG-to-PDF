Mini project overview  :-
This is a mini project to convert JPEG to PDF.
Upload a JPEG file to S3 bucket (which is input)
This automatically triggers Lamda function and the python program
After conversion, the PDF file is stored in another S3 bucket (which is output)

Infrastructure :-
1. S3 bucket
2. Lambda
3. IAM

Devops :-
1. The terraform files are going to be pushed via VS code to Github
2. These terraform files will have .github/workflow with the CI part yaml in them
3. Main branch will be protected. So will have development branch implemented.
4. Code change will be done in feature branch and then merge to development first.
5. After successful merge, it will be pushed to main.
