#!/bin/bash

# List of Azure regions to check for quota (update as needed)
REGIONS=("eastus2" "westus" "centralus" "uksouth" "francecentral")

SUBSCRIPTION_ID="1d5876cd-7603-407a-96d2-ae5ca9a9c5f3"
GPT_MIN_CAPACITY=30
TEXT_EMBEDDING_MIN_CAPACITY=130

# Authenticate using Managed Identity
echo "Authentication using Managed Identity..."
if ! az login --identity --tenant "52b39610-0746-4c25-a83d-d4f89fadedfe"; then
   echo "❌ Error: Failed to login using Managed Identity."
   exit 1
fi

echo "🔄 Validating required environment variables..."
if [[ -z "$SUBSCRIPTION_ID" || -z "$GPT_MIN_CAPACITY" || -z "$TEXT_EMBEDDING_MIN_CAPACITY" ]]; then
    echo "❌ ERROR: Missing required environment variables."
    exit 1
fi

echo "🔄 Setting Azure subscription..."
if ! az account set --subscription "$SUBSCRIPTION_ID"; then
    echo "❌ ERROR: Invalid subscription ID or insufficient permissions."
    exit 1
fi
echo "✅ Azure subscription set successfully."

# Define models and their minimum required capacities
declare -A MIN_CAPACITY=(
    ["OpenAI.Standard.gpt-4o"]=$GPT_MIN_CAPACITY
    ["OpenAI.Standard.text-embedding-ada-002"]=$TEXT_EMBEDDING_MIN_CAPACITY
)

VALID_REGION=""
for REGION in "${REGIONS[@]}"; do
    echo "----------------------------------------"
    echo "🔍 Checking region: $REGION"

    QUOTA_INFO=$(az cognitiveservices usage list --location "$REGION" --output json)
    if [ -z "$QUOTA_INFO" ]; then
        echo "⚠️ WARNING: Failed to retrieve quota for region $REGION. Skipping."
        continue
    fi

    INSUFFICIENT_QUOTA=false
    for MODEL in "${!MIN_CAPACITY[@]}"; do
        MODEL_INFO=$(echo "$QUOTA_INFO" | awk -v model="\"value\": \"$MODEL\"" '
            BEGIN { RS="},"; FS="," }
            $0 ~ model { print $0 }
        ')

        if [ -z "$MODEL_INFO" ]; then
            echo "⚠️ WARNING: No quota information found for model: $MODEL in $REGION. Skipping."
            continue
        fi

        CURRENT_VALUE=$(echo "$MODEL_INFO" | awk -F': ' '/"currentValue"/ {print $2}' | tr -d ',' | tr -d ' ')
        LIMIT=$(echo "$MODEL_INFO" | awk -F': ' '/"limit"/ {print $2}' | tr -d ',' | tr -d ' ')

        CURRENT_VALUE=${CURRENT_VALUE:-0}
        LIMIT=${LIMIT:-0}

        CURRENT_VALUE=$(echo "$CURRENT_VALUE" | cut -d'.' -f1)
        LIMIT=$(echo "$LIMIT" | cut -d'.' -f1)

        AVAILABLE=$((LIMIT - CURRENT_VALUE))

        echo "✅ Model: $MODEL | Used: $CURRENT_VALUE | Limit: $LIMIT | Available: $AVAILABLE"

        if [ "$AVAILABLE" -lt "${MIN_CAPACITY[$MODEL]}" ]; then
            echo "❌ ERROR: $MODEL in $REGION has insufficient quota."
            INSUFFICIENT_QUOTA=true
            break
        fi
    done

    if [ "$INSUFFICIENT_QUOTA" = false ]; then
        VALID_REGION="$REGION"
        break
    fi

done

if [ -z "$VALID_REGION" ]; then
    echo "❌ No region with sufficient quota found. Blocking deployment."
    echo "QUOTA_FAILED=true" >> "$GITHUB_ENV"
    exit 1
else
    echo "✅ Suggested Region: $VALID_REGION"
    echo "VALID_REGION=$VALID_REGION" >> "$GITHUB_ENV"
    exit 0
fi
