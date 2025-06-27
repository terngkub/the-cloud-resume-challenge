import json
import boto3


def lambda_handler(event, context):
    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table("nattapol-resume")
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
        "headers": {"Access-Control-Allow-Origin": "https://resume.nattapol.com"},
        "body": response_body,
    }
