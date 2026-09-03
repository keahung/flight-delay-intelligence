-- Anthropic model connection. Confluent Flink supports Anthropic natively, so no
-- AWS Bedrock is required even though this cluster runs on GCP.
-- Substitute ${ANTHROPIC_API_KEY} from .env -- do NOT commit a real key.
CREATE CONNECTION anthropic_conn WITH (
  'type'     = 'anthropic',
  'endpoint' = 'https://api.anthropic.com/v1/messages',
  'api-key'  = '${ANTHROPIC_API_KEY}'
);
