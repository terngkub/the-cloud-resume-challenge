# The AWS Cloud Resume Chellenge

* This is my implementation of the [AWS Cloud Resume Challenge](https://cloudresumechallenge.dev/docs/the-challenge/aws/).
* You can visit my production resume website on this link [resume.nattpaol.com](https://resume.nattapol.com).


## Components

The projects contain 6 components.

1. **Identity**

    I set up the accounts AWS Organization and IAM Identity Center. I don't include the implementation details in this repository because the account setup can be used with other projects as well.

2. **Front-end**

   The front-end contains my online resume website in HTML, CSS, and JavaScript.

3. **Back-end**

   The back-end contains the visitor counter API code.

4. **Tests**

   I set up smoke tests using Playwright to test the visitor counter behavior.

5. **Infrastructure as Code**

   I use Terraform to manage the infrastructures.
   
6. **CI/CD**

   I use GitHub Actions for CI/CD.

The code for each components are mapped to the directories as below.
|Component|Directory|
|---|---|
|Front-end|website/|
|Back-end|api/|
|Tests|tests/|
|Infrastructure as Code|terraform/|
|CI/CD|.github/workflows/|

There are also Git related files at the root of the project.
* .gitignore
* .gitattributes


## How to work with this repository


### Updating the front-end and back-end code.

You can directly edit the code on these directories. After you commit the changes, GitHub Actions will automatically build, deploy, and test the changes.

In case that there is a problem with the changes, I recommend reverting the commit. This will trigger the redeploy and roll back the changes.


### Run the smoke tests locally

I use Playwright for testing here. You can run it with pytest.

Set up
1. Create a virtual environment
   ```
   python3 -m venv .env
   ```
2. Activate the virtual environment
   ```
   source .env/bin/activate
   ```
3. Install dependencies
   ```
   python3 -m pip install -r requirements.txt
   ```

Run the tests
1. Activate the virtual environment
   ```
   source .env/bin/activate
   ```
2. Run the tests
   ```
   pytest
   ```
   This will run the smoke tests on the production website.


### Update the infrastructure

1. Sign in to the IAM Identity Center and get a temporary access key.
2. Export the temporary access key
3. Go to the environment directory you want to update
   ```
   cd terraform/environments/prod
   ```
4. If this is a first time, init Terraform.
   ```
   terraform init
   ```
5. Make any changes, and plan the changes.
   ```
   terraform plan -out tf.plan
   ```
6. Deploy
   ```
   terraform apply tf.plan
   ```