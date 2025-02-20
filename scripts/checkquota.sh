#!/bin/bash

# Set your Azure Subscription ID and Region
SUBSCRIPTION_ID="1d5876cd-7603-407a-96d2-ae5ca9a9c5f3"
REGION="eastus2"
GPT_MIN_CAPACITY=130  # Define minimum available capacity required
TEXT_EMBEDDING_MIN_CAPACITY=30  # Define minimum available capacity required

# Set Azure subscription
az account set --subscription "$SUBSCRIPTION_ID"

echo "Account set successfully"

# Fetch quota details from Azure
QUOTA_INFO=$(az cognitiveservices usage list --location "$REGION" --output json)

# Define models to check
MODELS=("OpenAI.Standard.gpt-4o" "OpenAI.Standard.text-embedding-ada-002")

# Initialize flag for insufficient quota
INSUFFICIENT_QUOTA=false

# Loop through each model and check quota
for MODEL in "${MODELS[@]}"; do
    echo "----------------------------------------"
    echo "🔍 Checking model: $MODEL"

    # Extract JSON block for the exact model (ensuring an exact match with awk)
    MODEL_INFO=$(echo "$QUOTA_INFO" | awk -v model="\"value\": \"$MODEL\"" '
        BEGIN { RS="},"; FS="," }
        $0 ~ model { print $0 }
    ')

    # Skip if no exact match found
    if [ -z "$MODEL_INFO" ]; then
        echo "⚠️ No exact match found for model: $MODEL. Skipping."
        continue
    fi

    # Extract currentValue and limit
    CURRENT_VALUE=$(echo "$MODEL_INFO" | awk -F': ' '/"currentValue"/ {print $2}' | tr -d ',' | tr -d ' ')
    LIMIT=$(echo "$MODEL_INFO" | awk -F': ' '/"limit"/ {print $2}' | tr -d ',' | tr -d ' ')

    # Default to 0 if empty
    CURRENT_VALUE=${CURRENT_VALUE:-0}
    LIMIT=${LIMIT:-0}

    # Convert to integer (remove decimal part)
    CURRENT_VALUE=$(echo "$CURRENT_VALUE" | cut -d'.' -f1)
    LIMIT=$(echo "$LIMIT" | cut -d'.' -f1)

    # Calculate available capacity
    AVAILABLE=$((LIMIT - CURRENT_VALUE))

    # Output model details
    echo "✅ Model: $MODEL | Used: $CURRENT_VALUE | Limit: $LIMIT | Available: $AVAILABLE"
    echo "----------------------------------------"

    # Check if available quota is below the minimum required
    if [ "$AVAILABLE" -lt "$GPT_MIN_CAPACITY" ]; then
        echo "⚠️  Warning: Model $MODEL has only $AVAILABLE capacity left, which is below the required minimum ($MIN_CAPACITY)."
        INSUFFICIENT_QUOTA=true
    fi
done

# Fail pipeline if quota is insufficient
if [ "$INSUFFICIENT_QUOTA" = true ]; then
    echo "❌ Quota is insufficient for one or more models. Exiting with failure."
    exit 1
fi

echo "✅ All models have sufficient quota."
exit 0
