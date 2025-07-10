provider "random" {}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

# Lambda execution role
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Effect = "Allow"
    }]
  })
}

# IAM policy to allow Lambda access to ECR
resource "aws_iam_policy" "lambda_ecr_access" {
  name = "LambdaECRAccessPolicy-${random_string.suffix.result}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      Resource = "*"
    }]
  })
}

resource "aws_ecr_repository_policy" "allow_lambda_pull" {
  repository = "lambda-repo" 

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowLambdaPull",
        Effect    = "Allow",
        Principal = {
          AWS = aws_iam_role.lambda_exec_role.arn
        },
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
      }
    ]
  })
}


# Attach ECR policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_ecr" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_ecr_access.arn
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function using container image
resource "aws_lambda_function" "container_lambda" {
  function_name = "container-lambda-${random_string.suffix.result}"
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  image_uri     = var.image_uri
  timeout       = 30
  memory_size   = 512

  environment {
    variables = {}
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_ecr
  ]
}

# Create API Gateway HTTP API
resource "aws_apigatewayv2_api" "http_api" {
  name          = "lambda-http-api-${random_string.suffix.result}"
  protocol_type = "HTTP"
}

# API Gateway integration
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.container_lambda.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Route for API Gateway
resource "aws_apigatewayv2_route" "lambda_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"

  depends_on = [aws_apigatewayv2_integration.lambda_integration]
}

# Default stage for deployment
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# Permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.container_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
