# Review Rules Index

Personalized code review rules extracted from technotronic12's PR comments across windward-ltd repositories.
Source: 322 comments across 34 PRs (user-gql-service, ww-backoffice, and others).

## Rule Files

| File | When to Load | Scope |
|------|-------------|-------|
| [REVIEW-RULES-COMMON.md](./REVIEW-RULES-COMMON.md) | **Always** | Types, naming, cleanup, testing basics — applies to all code |
| [REVIEW-RULES-BACKEND.md](./REVIEW-RULES-BACKEND.md) | `.ts` files in `src/services/`, `src/dal/`, `src/model/`, `src/routes/`, `src/schema/`, `src/utils/`, `src/helpers/`, `src/validations/` and their tests | Node.js, GraphQL, DAL, services, architecture |
| [REVIEW-RULES-FRONTEND.md](./REVIEW-RULES-FRONTEND.md) | `.tsx` files, `src/components/`, `src/stores/`, `src/hooks/` and their tests | React, MobX, Material-UI, hooks, components |

**If a PR has both backend and frontend changes**, load COMMON + both domain files.

## Detection Logic

```
Always:
  → Load REVIEW-RULES-COMMON.md

For each changed file:
  if extension is .tsx OR path contains /components/ OR /stores/ OR /hooks/:
    → Load REVIEW-RULES-FRONTEND.md
  if extension is .ts (not .tsx) OR path contains /services/ OR /dal/ OR /model/ OR /routes/ OR /schema/:
    → Load REVIEW-RULES-BACKEND.md
  if both:
    → Load both domain files
```
