resource "aws_iam_role" "lambda_exec_role" {
    name = "lambda-exec-role-1"
    assume_role_policy = jsonencode({
        Version    = "2012-10-17",
        Statement  = [{
            Action = "sts:AssumeRole",
            Principal = {
                Service = "lambda.amazonaws.com"
            },
            Effect = "Allow"
           } 
        ]
    })
  
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
    role = aws_iam_role.lambda_exec_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "container_lambda" {
    function_name = "container-lambda"
    role     = aws_iam_role.lambda_exec_role.arn
    package_type = "Image"
    image_uri  = var.image_uri
    timeout   = 30
    memory_size  = 512
    
    environment {
      variables = {}
    }
}

resource "aws_apigatewayv2_api" "http_api" {
    name   = "lambda-http-api"
    protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
    api_id  = aws_apigatewayv2_api.http_api.id
    integration_type = "AWS_PROXY"
    integration_uri = aws_lambda_function.container_lambda.invoke_arn
    integration_method = "POST"
    payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "lambda_route" {
    api_id = aws_apigatewayv2_api.http_api.id
    route_key = "ANY /"
    target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"

    depends_on = [ aws_apigatewayv2_integration.lambda_integration ]
}

resource "aws_apigatewayv2_stage" "default" {
    api_id   = aws_apigatewayv2_api.http_api.id
    name = "$default"
    auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
    statement_id = "AllowAPIGatewayInvoke"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.container_lambda.function_name
    principal = "apigateway.amazonaws.com"
    source_arn  = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}