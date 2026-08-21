# Descon Manpower API

Rails 8.1 API for the Descon Manpower application, based on the reusable Rails API foundation.

- Devise staff authentication
- JWT access tokens with rotating database-backed refresh tokens
- Pundit authorization
- Solid Queue, Solid Cache, Solid Cable
- RSpec, RuboCop, Brakeman, Bundler Audit, SimpleCov
- Docker and Docker Compose
- OpenAPI validation

## Docker development

```bash
docker compose up --build
```

The API is available at `http://localhost:3000` and the readiness endpoint is:

```bash
curl http://localhost:3000/api/v1/health/ready
```

Database preparation runs automatically when the API container starts.

## Native development

```bash
bundle install
cp .env.development .env
bundle exec rails db:prepare
bundle exec rails server
```

## Quality

```bash
bundle exec rails zeitwerk:check
bundle exec rspec
bundle exec rubocop
bin/brakeman --no-pager
bundle exec bundle-audit check --update
bundle exec rails openapi:validate
```

## API Docs

This project includes both the raw OpenAPI spec and a browser-based Redoc page.

- Browser docs URL: `/api-docs`
- OpenAPI URL: `/openapi/openapi.yaml`
- OpenAPI source file: `openapi/openapi.yaml`
- Validation command: `bundle exec rails openapi:validate`

To share docs with API consumers, use one of these approaches:

- Share the Redoc page at `/api-docs`
- Share the raw OpenAPI document at `/openapi/openapi.yaml`
- Import `openapi/openapi.yaml` into Swagger UI, Postman, or Stoplight

## I18n

API message localization is enabled by default with English as the default locale and English fallbacks for missing keys.

- Supported locales are configured through `APP_SUPPORTED_LOCALES` and default to `en,ur`
- Locale resolution order is `X-Locale`, then `Accept-Language`, then default `en`
- Standard JSON API responses include `Content-Language` and `Vary: Accept-Language, X-Locale`
- Request locale switching is isolated per request with `I18n.with_locale`
- Test mode raises on missing translations

Examples:

```bash
curl -H "X-Locale: ur" http://localhost:3000/api/v1/health/live
curl -H "Accept-Language: ur-PK,ur;q=0.9,en;q=0.8" http://localhost:3000/api/v1/health/live
```

To add a new language:

1. Add the locale code to `APP_SUPPORTED_LOCALES`
2. Create `config/locales/api.<locale>.yml`
3. Add translated Devise or model-level keys if that project needs them

Database-backed translated content should stay out of static locale files. Store translated fields explicitly, for example `title_en` and `title_ur`, or use a translation layer such as Mobility only when the project actually needs database-level translated content.

## API

- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `DELETE /api/v1/auth/logout`
- `GET /api/v1/users/profile`
- `GET /api/v1/health/live`
- `GET /api/v1/health/ready`
