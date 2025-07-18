# Terraform


## Deployment Steps

* Enable Thailand region
* Create an S3 bucket to store a Terraform state
    * Prod: nattapol-crc-prod-terraform
    * Dev: nattapol-crc-dev-terraform
* Import the website certificate to ACM in us-east-1
* Deploy the infrastructure with terraform
    ```
    # Get the access key from IAM Identity Center sign in
    # Export the access key
    cd environments/prod
    terraform init
    terraform plan -out tf.plan
    terraform apply tf.plan
    ```
* Run GitHub Actions to deploy the front-end and back-end
* Set up DNS CNAME to point to CloudFront distribution