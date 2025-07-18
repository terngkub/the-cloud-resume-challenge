import boto3
import json
import os


def lambda_handler(event, context):
    table_name = os.environ.get("DYNAMODB_TABLE_NAME")

    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table(table_name)
    response = table.update_item(
        Key={"stats": "visitor-counter"},
        UpdateExpression="ADD #count :val",
        ExpressionAttributeNames={"#count": "count"},
        ExpressionAttributeValues={":val": 1},
        ReturnValues="UPDATED_NEW",
    )
    response_body = json.dumps(
        {"visitor-counter": int(response["Attributes"]["count"])}
    )
    return {
        "statusCode": 200,
        "headers": {
            "Access-Control-Allow-Origin": f'https://{os.environ.get("FULL_DOMAIN_NAME")}'
        },
        "body": response_body,
    }
