CREATE MODEL delay_llm
INPUT (prompt STRING)
OUTPUT (response STRING)
WITH (
  'provider' = 'anthropic',
  'task' = 'text_generation',
  'anthropic.connection' = 'anthropic_conn',
  'anthropic.params.model' = 'claude-opus-5',
  'anthropic.params.max_tokens' = '1024'
);
