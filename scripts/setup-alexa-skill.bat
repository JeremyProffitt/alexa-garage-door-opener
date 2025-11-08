@echo off
REM ###########################################################################
REM Alexa Skill Setup Script
REM
REM This script automates the creation and deployment of the Alexa skill
REM using the ASK CLI (Alexa Skills Kit Command Line Interface)
REM
REM Prerequisites:
REM - ASK CLI installed (npm install -g ask-cli)
REM - ASK CLI configured (ask configure) OR ALEXA_LWA_TOKEN env variable set
REM - AWS SAM deployed (Lambda ARN available)
REM
REM Environment Variables:
REM   ALEXA_LWA_TOKEN - LWA (Login with Amazon) refresh token for ASK CLI auth
REM
REM Usage:
REM   scripts\setup-alexa-skill.bat [LAMBDA_ARN]
REM   set ALEXA_LWA_TOKEN=your_token && scripts\setup-alexa-skill.bat [LAMBDA_ARN]
REM ###########################################################################

setlocal enabledelayedexpansion

REM Colors for output (Windows 10+)
set "RED=[91m"
set "GREEN=[92m"
set "YELLOW=[93m"
set "BLUE=[94m"
set "NC=[0m"

REM Function to print colored output
goto :main

:print_status
    echo %BLUE%^=^=^>%NC% %~1
    exit /b

:print_success
    echo %GREEN%✓%NC% %~1
    exit /b

:print_error
    echo %RED%✗%NC% %~1
    exit /b

:print_warning
    echo %YELLOW%⚠%NC% %~1
    exit /b

REM Function to check if ASK CLI is installed
:check_ask_cli
    where ask >nul 2>&1
    if %errorlevel% neq 0 (
        call :print_error "ASK CLI is not installed"
        echo Install it with: npm install -g ask-cli
        exit /b 1
    )

    call :print_success "ASK CLI is installed"
    exit /b 0

REM Function to configure ASK CLI with LWA token
:configure_ask_cli
    if not "%ALEXA_LWA_TOKEN%"=="" (
        call :print_status "Configuring ASK CLI with LWA token..."

        REM Create ASK CLI config directory
        if not exist "%USERPROFILE%\.ask" mkdir "%USERPROFILE%\.ask"

        REM Get current timestamp in ISO format (Windows PowerShell)
        for /f "tokens=*" %%i in ('powershell -Command "([DateTime]::UtcNow.AddHours(1)).ToString('yyyy-MM-ddTHH:mm:ss.000Z')"') do set "EXPIRES_AT=%%i"

        REM Create cli_config with LWA refresh token using PowerShell for JSON formatting
        powershell -Command "$config = @{profiles = @{default = @{aws_profile = 'default'; token = @{access_token = '%ALEXA_LWA_TOKEN%'; refresh_token = '%ALEXA_LWA_TOKEN%'; token_type = 'bearer'; expires_in = 3600; expires_at = '!EXPIRES_AT!'}; vendor_id = ''}}}; $config | ConvertTo-Json -Depth 5 | Set-Content '%USERPROFILE%\.ask\cli_config'"

        call :print_success "ASK CLI configured with LWA token"
        exit /b 0
    ) else (
        REM Check if manually configured
        if not exist "%USERPROFILE%\.ask\cli_config" (
            call :print_error "ASK CLI is not configured"
            echo Either set ALEXA_LWA_TOKEN environment variable or run: ask configure
            exit /b 1
        )

        call :print_success "Using existing ASK CLI configuration"
        exit /b 0
    )

REM Function to get Lambda ARN
:get_lambda_arn
    if not "%~1"=="" (
        set "LAMBDA_ARN=%~1"
        call :print_success "Using provided Lambda ARN: !LAMBDA_ARN!"
        exit /b 0
    )

    call :print_status "Fetching Lambda ARN from AWS CloudFormation..."

    for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name garage-door-opener --query "Stacks[0].Outputs[?OutputKey=='AlexaSkillFunctionArn'].OutputValue" --output text 2^>nul') do set "LAMBDA_ARN=%%i"

    if "!LAMBDA_ARN!"=="" (
        call :print_error "Could not fetch Lambda ARN from CloudFormation"
        echo Please provide Lambda ARN as argument:
        echo   scripts\setup-alexa-skill.bat arn:aws:lambda:us-east-2:123456789012:function:...
        exit /b 1
    )

    call :print_success "Lambda ARN: !LAMBDA_ARN!"
    exit /b 0

REM Function to update skill.json with Lambda ARN
:update_skill_json
    call :print_status "Updating skill.json with Lambda ARN..."

    REM Get AWS account ID from Lambda ARN (5th field, separated by colons)
    for /f "tokens=5 delims=:" %%a in ("!LAMBDA_ARN!") do set "ACCOUNT_ID=%%a"

    REM Update skill.json using PowerShell for reliable file manipulation
    powershell -Command "(Get-Content 'alexa-skill\skill.json') -replace 'ACCOUNT_ID', '!ACCOUNT_ID!' | Set-Content 'alexa-skill\skill.json'"
    powershell -Command "(Get-Content 'alexa-skill\skill.json') -replace 'arn:aws:lambda:us-east-2:!ACCOUNT_ID!:function:garage-door-opener-alexa-skill', '!LAMBDA_ARN!' | Set-Content 'alexa-skill\skill.json'"

    call :print_success "skill.json updated"
    exit /b 0

REM Function to setup skill package structure
:setup_skill_package
    call :print_status "Setting up skill package structure..."

    cd alexa-skill

    REM Create skill package directory structure
    if not exist "skill-package\interactionModels\custom" mkdir "skill-package\interactionModels\custom"

    REM Copy skill manifest
    copy /Y skill.json skill-package\skill.json >nul

    REM Copy interaction model to proper location
    copy /Y interactionModel.json skill-package\interactionModels\custom\en-US.json >nul

    REM Create ask-resources.json for ASK CLI v2
    (
        echo {
        echo   "askcliResourcesVersion": "2020-03-31",
        echo   "profiles": {
        echo     "default": {
        echo       "skillMetadata": {
        echo         "src": "./skill-package"
        echo       }
        echo     }
        echo   }
        echo }
    ) > ask-resources.json

    call :print_success "Skill package structure created"
    cd ..
    exit /b 0

REM Function to create or update skill
:deploy_skill
    call :print_status "Deploying Alexa skill..."

    cd alexa-skill

    REM Setup skill package structure
    if not exist "ask-resources.json" (
        cd ..
        call :setup_skill_package
        cd alexa-skill
    )

    REM Use ASK CLI v2 deploy command
    call :print_status "Deploying skill with ASK CLI..."

    REM Run ask deploy
    ask deploy > "%TEMP%\ask-deploy.log" 2>&1
    set DEPLOY_RESULT=%errorlevel%

    if %DEPLOY_RESULT% equ 0 (
        REM Extract skill ID from .ask directory
        if exist ".ask\ask-states.json" (
            for /f "tokens=*" %%i in ('powershell -Command "(Get-Content '.ask\ask-states.json' | ConvertFrom-Json).profiles.default.skillId"') do set "SKILL_ID=%%i"
        )

        call :print_success "Skill deployment complete!"
        echo.
        if not "!SKILL_ID!"=="" (
            echo Skill ID: !SKILL_ID!
            echo.
        )
        echo Next steps:
        echo 1. Go to https://developer.amazon.com/alexa/console/ask
        echo 2. Find your skill: Garage Door Controller
        echo 3. Enable testing in Development
        echo 4. Test with: 'Alexa, ask garage door to press the button'
    ) else (
        call :print_error "Skill deployment failed"
        echo.
        echo Error log:
        type "%TEMP%\ask-deploy.log"
        echo.
        call :print_warning "Please check the error above or create skill manually using Alexa Developer Console"
        echo.
        echo Files ready for manual import:
        echo   - skill.json (skill manifest)
        echo   - interactionModel.json (interaction model)
    )

    cd ..
    exit /b 0

REM Function to add Lambda trigger permission
:add_lambda_permission
    call :print_status "Adding Alexa trigger permission to Lambda..."

    REM Extract function name from ARN (7th field)
    for /f "tokens=7 delims=:" %%a in ("!LAMBDA_ARN!") do set "FUNCTION_NAME=%%a"

    REM Add permission (will fail if already exists, which is fine)
    aws lambda add-permission --function-name "!FUNCTION_NAME!" --statement-id "AlexaSkill" --action "lambda:InvokeFunction" --principal "alexa-appkit.amazon.com" 2>nul

    call :print_success "Lambda permissions configured"
    exit /b 0

REM Function to test skill
:test_skill
    call :print_status "Testing skill connection..."

    echo.
    call :print_warning "Manual testing steps:"
    echo 1. Open Alexa Developer Console: https://developer.amazon.com/alexa/console/ask
    echo 2. Open 'Garage Door Controller' skill
    echo 3. Go to 'Test' tab
    echo 4. Enable testing: Development
    echo 5. Type or say: 'ask garage door for status'
    echo.
    exit /b 0

REM Main script
:main
    echo.
    echo ╔══════════════════════════════════════════════════════════════════╗
    echo ║       Alexa Skill Automated Setup Script                        ║
    echo ╚══════════════════════════════════════════════════════════════════╝
    echo.

    REM Check prerequisites
    call :check_ask_cli
    if %errorlevel% neq 0 exit /b 1

    REM Configure ASK CLI with LWA token or check existing config
    call :configure_ask_cli
    if %errorlevel% neq 0 exit /b 1

    REM Get Lambda ARN
    call :get_lambda_arn %1
    if %errorlevel% neq 0 exit /b 1

    REM Update configuration files
    call :update_skill_json
    if %errorlevel% neq 0 exit /b 1

    REM Deploy skill
    call :deploy_skill
    if %errorlevel% neq 0 exit /b 1

    REM Add Lambda permissions
    call :add_lambda_permission

    REM Show testing instructions
    call :test_skill

    echo.
    echo ════════════════════════════════════════════════════════════════
    echo   SETUP COMPLETE
    echo ════════════════════════════════════════════════════════════════
    echo.
    call :print_success "Alexa skill setup finished!"
    echo.
    echo Lambda ARN: !LAMBDA_ARN!
    echo.
    echo Files created:
    echo   - alexa-skill\skill.json (updated with Lambda ARN)
    echo   - alexa-skill\interactionModel.json
    echo.
    echo For manual setup, see: docs\alexa-skill-setup.md
    echo.

endlocal
