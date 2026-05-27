# PII Entities

Here's a reference list of common PII (Personally Identifiable Information) entity types, formatted as YAML. This matches the taxonomy used by most PII detection tools (Microsoft Presidio, AWS Comprehend, Google DLP, etc.) which is what LiteLLM-style guardrails typically integrate with.

```yaml
pii_entities:
  # Identity
  - PERSON                    # Full names
  - FIRST_NAME
  - LAST_NAME
  - USERNAME
  - AGE
  - DATE_OF_BIRTH
  - GENDER
  - NATIONALITY
  - MARITAL_STATUS

  # Contact
  - EMAIL_ADDRESS
  - PHONE_NUMBER
  - FAX_NUMBER
  - URL
  - IP_ADDRESS                # IPv4 / IPv6
  - MAC_ADDRESS

  # Location
  - LOCATION                  # Generic place
  - STREET_ADDRESS
  - CITY
  - STATE
  - ZIP_CODE
  - COUNTRY
  - GPS_COORDINATES

  # Government / National IDs
  - US_SSN                    # US Social Security Number
  - US_ITIN                   # Individual Taxpayer ID
  - US_DRIVER_LICENSE
  - US_PASSPORT
  - UK_NHS                    # UK National Health Service number
  - UK_NINO                   # National Insurance Number
  - EU_PASSPORT
  - EU_NATIONAL_ID
  - EU_DRIVER_LICENSE
  - ES_NIF                    # Spain
  - ES_NIE
  - IT_FISCAL_CODE            # Italy codice fiscale
  - FR_INSEE                  # France
  - DE_TAX_ID                 # Germany
  - IN_AADHAAR                # India
  - IN_PAN
  - AU_TFN                    # Australia Tax File Number
  - AU_MEDICARE
  - SG_NRIC                   # Singapore

  # Financial
  - CREDIT_CARD
  - CREDIT_CARD_CVV
  - IBAN_CODE
  - SWIFT_CODE
  - US_BANK_ACCOUNT
  - US_ROUTING_NUMBER
  - CRYPTO_WALLET             # BTC, ETH addresses

  # Medical
  - MEDICAL_LICENSE
  - MEDICAL_RECORD_NUMBER
  - HEALTH_INSURANCE_NUMBER
  - DIAGNOSIS
  - MEDICATION

  # Employment / Org
  - EMPLOYEE_ID
  - JOB_TITLE
  - ORGANIZATION
  - SALARY

  # Digital / Credentials
  - PASSWORD
  - API_KEY
  - ACCESS_TOKEN
  - PRIVATE_KEY               # SSH, PGP, TLS private keys
  - AWS_ACCESS_KEY
  - AWS_SECRET_KEY
  - AZURE_KEY
  - GCP_API_KEY

  # Vehicle / Asset
  - LICENSE_PLATE
  - VIN                       # Vehicle Identification Number

  # Biometric
  - FINGERPRINT
  - FACE_ID
  - VOICE_PRINT
  - DNA_SEQUENCE

  # Date/time
  - DATE_TIME                 # Often considered quasi-identifier
```

# Notes on using this with LiteLLM

If you're configuring a guardrail in LiteLLM (the YAML hint suggests you might be), the format is typically:

```yaml
guardrails:
  - guardrail_name: "presidio-pii-masking"
    litellm_params:
      guardrail: presidio
      mode: "pre_call"
      pii_entities_config:
        EMAIL_ADDRESS: "MASK"
        CREDIT_CARD: "BLOCK"
        US_SSN: "BLOCK"
        PHONE_NUMBER: "MASK"
        PERSON: "MASK"
        IP_ADDRESS: "MASK"
      presidio_analyzer_api_base: "http://presidio-analyzer:3000"
      presidio_anonymizer_api_base: "http://presidio-anonymizer:3000"
```

Common actions per entity:
- `MASK` — replace with `<EMAIL_ADDRESS>` or similar placeholder
- `BLOCK` — reject the request outright
- `REDACT` — replace with `*****`
- `HASH` — replace with a hash of the original

## Caveats

The exact entity names depend on which detector you're plugging in — Presidio uses `US_SSN` and `EMAIL_ADDRESS`, AWS Comprehend uses `SSN` and `EMAIL`, Google DLP uses `US_SOCIAL_SECURITY_NUMBER` and `EMAIL_ADDRESS`. Check your detector's docs for the canonical names before pasting these into a config.

Were you trying to configure a specific guardrail (Presidio, AWS, Lakera, etc.), or just looking for a general reference? I can tailor this to the specific tool.