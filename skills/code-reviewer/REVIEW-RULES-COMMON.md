# Common Review Rules

Rules that apply to **all code** — backend and frontend alike. Always loaded alongside the domain-specific rule files.
Source: 322 comments by technotronic12 across 34 windward-ltd PRs.

---

## Severity Levels

| Level | Meaning | Action |
|-------|---------|--------|
| **CRITICAL** | Must fix before merge | Block PR |
| **WARNING** | Should fix, may approve with comment | Request changes |
| **INFO** | Nice to have, suggestion | Comment only |

---

## Types & Naming

### C-01: Interface names should not start with "I"
**Severity:** WARNING | **Category:** Types

Don't prefix interface names with `I` unless it is the established convention in the project you're working on. Check the existing codebase first — if the project consistently uses `I` prefix (e.g. `IConsumer`, `IMSKConsumerOptions`), follow that convention. Otherwise, use plain names.

```ts
// BAD — in a project that doesn't use I prefix
interface IUserConfig { ... }
interface IDeleteRequest { ... }

// GOOD — plain descriptive name
interface UserConfig { ... }
interface DeleteOrganizationRequest { ... }

// ALSO GOOD — if the project already uses I prefix consistently
interface IUserConfig { ... }  // matches existing IConsumer, IMSKConsumerOptions, etc.
```

> Check existing interfaces in the project before suggesting a name. Follow the established pattern.

---

### C-02: Avoid `any` — ask why
**Severity:** WARNING | **Category:** Types

Question every `any`. If a parameter needs `any`, there should be an explicit justification. For catch blocks, `error: any` is acceptable since we assume errors are Error objects, not strings or primitives.

> "why any?"
> "why any[]?"
> "error: any because neither we nor libraries throw strings or other primitives as errors"

---

### C-03: Descriptive variable names — no abbreviations, no lifecycle noise, no synonym redundancy
**Severity:** WARNING | **Category:** Naming

Use full, descriptive names. No single-letter variables except in trivial lambdas. Avoid three common naming anti-patterns:

**1. Abbreviations**
```ts
// BAD
const acc = accounts.find(a => a.id === id);
// GOOD
const account = accounts.find(account => account.id === id);
```

**2. Lifecycle/provenance prefixes in parameter names** — parameters should say what the data IS, not how it was obtained or its history.
```ts
// BAD — "migrated" is how the IDs were obtained, not what they are
async function createGroupWithUsers(organization, migratedFronteggUsersIds) { ... }

// GOOD — just describe the data
async function createGroupWithUsers(organization, fronteggUsersIds) { ... }
```

**3. Synonym redundancy in identifiers** — don't use two words that mean the same thing in the same name.
```ts
// BAD — "app" and "application" are synonyms; pick one
function getMongoAppByFronteggApplicationId(applicationId) { ... }

// GOOD
function getMongoApplicationByFronteggId(applicationId) { ... }
```

**4. Test mock variable names** — mock variables follow the same rules: no abbreviations, no generic names. The name should describe what the mock represents.
```ts
// BAD — abbreviated
const mockReq = { wwExecutionContext: { user: { ... } } };
// GOOD — full descriptive name
const mockRequestContext = { wwExecutionContext: { user: { ... } } };

// BAD — too generic, says nothing about the shape
const mockData = { organizationId: '123', organizationName: 'Acme' };
// GOOD — describes what this data represents
const mockCreateDeleteOrganizationInput = { organizationId: '123', organizationName: 'Acme' };
```

**5. Map/collection names must state "from what → to what"** — a `Map` variable named `usersMap` or `accessorsMap` is too vague. State what keys map to what values, so the reader understands the data structure without inspecting the code.
```ts
// BAD — "map of what?"
const usersMap = new Map(users.map(user => [user.id, user]));
const existingPermissions = new Map();  // unclear what keys/values are

// GOOD — name conveys the key→value relationship
const userById = new Map(users.map(user => [user.id, user]));
const permissionByResourceAndAccessor = new Map();  // key: "resourceId:accessorId", value: role
```

> "no need to shorten, use `account` instead of `acc`"
> "firstOrganization, secondOrganization is better than a,b"
> "I don't like having here 'migrated' — createGroupWithUsers should probably just get userIds not migratedUserIds"
> "you have app and application both in the same name which is weird"
> "mockRequestContext?"
> "maybe something better than mockData?"
> "map of what? name should be clear intent (what and more importantly why), not the actual implementation details"
> "map from what to what?"

---

## Code Cleanup

### C-04: Remove comments
**Severity:** WARNING | **Category:** Cleanup

No comments in production code. Extract logic to a descriptively-named function instead.

```ts
// BAD
// Check if the user has permission to delete
if (user.role === 'admin' && org.status !== 'active') { ... }

// GOOD
if (canDeleteOrganization(user, org)) { ... }
```

> "please remove all comments"
> "maybe this logic should be extracted to a function with a meaningful name rather than adding a comment?"

---

### C-05: Extract magic strings to constants
**Severity:** CRITICAL | **Category:** Cleanup

Strings used in multiple places must be extracted to named constants and reused in both production code and tests.

```ts
// BAD
throw new Error('Account already exists');
// test:
expect(error.message).toBe('Account already exists');

// GOOD
export const ACCOUNT_ALREADY_EXISTS = 'Account already exists';
throw new Error(ACCOUNT_ALREADY_EXISTS);
expect(error.message).toBe(ACCOUNT_ALREADY_EXISTS);
```

> "let's extract string and reuse everywhere"
> "let's extract those errors to a const and reuse them both in prod and tests"

---

### C-06: No new .js files
**Severity:** CRITICAL | **Category:** Cleanup

All new files must be TypeScript (.ts or .tsx). If modifying a .js file significantly, convert to .ts.

> "please, do not add new `.js` files. We have Typescript now."

---

### C-07: Import ordering and absolute paths
**Severity:** INFO | **Category:** Cleanup

External imports first, then internal. Use absolute imports with `/` prefix. No linebreaks between imports within a group.

```ts
// BAD
import { helper } from '../../utils/helper';
import express from 'express';

// GOOD
import express from 'express';

import { helper } from '/utils/helper';
```

```tsx
// BAD (frontend)
import { helper } from '../../utils/helper';
import React from 'react';

// GOOD (frontend)
import React from 'react';
import { Button } from '@material-ui/core';

import { helper } from '/utils/helper';
```

> "let's sort imports so external imports are on top and internal are on the bottom"
> "let's prefix all imports with `/`"
> "no need to add linebreak between imports"

---

### C-08: Linebreak formatting — especially before `if` statements
**Severity:** WARNING | **Category:** Cleanup

Add a linebreak before `if` statements — this makes branching points in the code easy to spot when scanning vertically. Also add a linebreak before `expect` in tests (exception: two-liner tests). Remove redundant consecutive linebreaks. No linebreaks between imports within the same group.

```ts
// BAD — if blends into surrounding code
const voiId = voi.id.toString();
if (!voisAccessorsMap.has(voiId)) {
  voisAccessorsMap.set(voiId, []);
}

// GOOD — linebreak above if makes the branch visually distinct
const voiId = voi.id.toString();

if (!voisAccessorsMap.has(voiId)) {
  voisAccessorsMap.set(voiId, []);
}
```

> "linebreak above if"
> "linebrak above if"
> "return above expect (I make an exception when the test is a two-liner)"
> "redundant linebreak"

---

## Testing

### C-09: Extract common setup to beforeEach
**Severity:** CRITICAL | **Category:** Testing

When multiple tests share setup (mocks, stubs, renders) **or the same execution call**, extract to `beforeEach`. Group related tests under `describe`. This applies to mock setup AND to the function-under-test call when multiple tests invoke the same call and then assert different aspects of the result.

```ts
// GOOD (backend) — mock setup in beforeEach
describe('when service returns data', () => {
  beforeEach(() => {
    jest.spyOn(Service, 'get').mockResolvedValue(mockData);
  });
  it('returns formatted result', async () => { ... });
  it('caches the response', async () => { ... });
});
```

```ts
// BAD — same execution call repeated in every test
it('should have correct status', async () => {
  const actual = await controller.create(mockInput, mockReq);
  expect(actual.status).toBe('pending');
});
it('should have empty confirmations', async () => {
  const actual = await controller.create(mockInput, mockReq);
  expect(actual.confirmations).toEqual([]);
});

// GOOD — execution call extracted to beforeEach
let actualDeletion;
beforeEach(async () => {
  actualDeletion = await controller.create(mockInput, mockReq);
});
it('should have correct status', () => {
  expect(actualDeletion.status).toBe('pending');
});
it('should have empty confirmations', () => {
  expect(actualDeletion.confirmations).toEqual([]);
});
```

```tsx
// GOOD (frontend)
describe('DeleteOrganizationForm', () => {
  beforeEach(() => {
    render(<DeleteOrganizationForm {...defaultProps} />);
  });
  it('renders the form', () => { ... });
  it('shows validation errors', () => { ... });
});
```

> "let's extract to a beforeEach, you can combine under a describe if needed"
> "consider grouping these tests under a describe and do this rendering in a beforeEach"
> "extract the rendering and the confirmButton lookup to a beforeEach"
> "then, you can extract `const organizationDeletion = await controller.create(mockData, mockReq);` to beforeEach"

---

### C-10: Extract and reuse test data with mock prefix
**Severity:** CRITICAL | **Category:** Testing

No duplicate data across tests. Shared values at describe-level with `mock` prefix. Return values use `actual` prefix — and make the name descriptive: `actualUser`, `actualConfig` — not just `actualResult`.

**Casing**: Use camelCase for mock variables (`mockUserId`, `mockOrgName`). UPPER_CASE is reserved for production constants only — not for test fixtures.

```ts
// BAD — UPPER_CASE for mock values
const MOCK_USER_ID = aUserId;
const MOCK_USERNAME = aUsername;
const MOCK_ORG_ID = vmsAndComplianceOrgId;

// GOOD — camelCase with mock prefix
const mockUserId = aUserId;
const mockUsername = aUsername;
const mockOrgId = vmsAndComplianceOrgId;

const mockUserRequest = { name: 'test-user', role: 'admin' };

it('creates user', async () => {
  const actualUser = await create(mockUserRequest);
  expect(actualUser.name).toBe(mockUserRequest.name);
});
```

> "some fields can be extracted to some mockBaseOrganization or similar"
> "extract and reuse both in prod and tests"
> "we usually use UPPER_CASE for production constants that don't change. For mocks, prefer using `mockUserId`, `mockUsername`, etc"

---

### C-11: Rename generic `result` to descriptive names
**Severity:** WARNING | **Category:** Testing

Never use `result`. Use a descriptive name with the `actual` prefix that reflects what was returned: `actualUser`, `actualFronteggApplicationIds`, `actualConfig`.

> "let's rename result to something more descriptive, here and everywhere"
> "`const createdUser` or `const actualUser`. same everywhere"

---

### C-12: Remove unnecessary test timeouts
**Severity:** WARNING | **Category:** Testing

Question every `timeout` in test blocks.

> "do we need this timeout? here and everywhere"

---

## Error Handling

### C-13: Avoid try-catch — question every try-catch block
**Severity:** WARNING | **Category:** Error Handling

Question every try-catch. In most cases, errors should propagate to the caller or to a centralized error handler. Wrapping code in try-catch often hides bugs, swallows context, or leads to silent failures. Only catch when you have a specific recovery strategy.

```ts
// BAD — catches and re-throws with less context
async function getUser(id: string): Promise<User> {
  try {
    return await userDal.findById(id);
  } catch (error) {
    throw new Error('Failed to get user');
  }
}

// GOOD — let it propagate, the caller or error middleware handles it
async function getUser(id: string): Promise<User> {
  return userDal.findById(id);
}

// OK — catching for a specific recovery strategy
async function getOrCreateUser(id: string): Promise<User> {
  const existing = await userDal.findById(id);
  if (!existing) {
    return userDal.create({ id });
  }
  return existing;
}
```

> "why do we need the try-catch here?"
> "let it throw — the error middleware will handle it"

---

### C-14: Don't explicitly `return undefined`
**Severity:** WARNING | **Category:** Cleanup

Use a bare `return;` or omit the return entirely. Explicitly returning `undefined` adds noise without meaning.

```ts
// BAD
function findUser(id: string): User | undefined {
  const user = users.get(id);
  if (!user) {
    return undefined;
  }
  return user;
}

// GOOD
function findUser(id: string): User | undefined {
  const user = users.get(id);
  if (!user) {
    return;
  }
  return user;
}

// ALSO GOOD — simpler
function findUser(id: string): User | undefined {
  return users.get(id);
}
```

> "no need to explicitly return undefined"
> "just `return;` or omit"

---

## Testing (continued)

### C-15: `it.each` — 2-3 params max, no `if` inside test body
**Severity:** WARNING | **Category:** Testing

Use `it.each` only when all cases share the exact same assertion flow with 2-3 varying parameters. If you need an `if` statement inside the test body, split into separate `it` blocks instead — conditional logic inside a parameterized test hides what's actually being tested.

```ts
// BAD — if statement inside it.each
it.each([
  ['admin', true, 'granted'],
  ['viewer', false, undefined],
])('should handle %s role', (role, hasAccess, expectedResult) => {
  const result = checkAccess(role);
  if (hasAccess) {
    expect(result).toBe(expectedResult);
  } else {
    expect(result).toBeUndefined();
  }
});

// GOOD — separate tests for different assertion flows
it('should grant access for admin role', () => {
  expect(checkAccess('admin')).toBe('granted');
});

it('should deny access for viewer role', () => {
  expect(checkAccess('viewer')).toBeUndefined();
});

// GOOD — it.each for same assertion flow, 2 params
it.each([
  ['admin', 'granted'],
  ['editor', 'granted'],
  ['superadmin', 'granted'],
])('should grant access for %s role', (role, expected) => {
  expect(checkAccess(role)).toBe(expected);
});
```

> "let's not use it.each here — the test cases have different assertion flows"
> "if you need an if inside the test, split it"

---

## Naming (continued)

### C-16: File type suffixes — formatter, helper, utils, service
**Severity:** INFO | **Category:** Naming

Use the correct file suffix to indicate the file's role and dependency profile:

| Suffix | Meaning | Dependencies |
|--------|---------|-------------|
| `*.formatter.ts` | Pure data transformation | None — pure functions only |
| `*.helper.ts` | Infrastructure-dependent logic | May depend on DB, HTTP, external services |
| `*.utils.ts` | Pure utility functions | None — generic reusable utilities |
| `*.service.ts` | Infrastructure service | Depends on DAL, external APIs, other services |

```
// BAD — helper that has no infrastructure dependencies
src/helpers/date.helper.ts  // only does pure date formatting

// GOOD — it's a formatter (pure function)
src/formatters/date.formatter.ts

// BAD — service-level logic in a helper
src/helpers/kafka.helper.ts  // creates Kafka producers, connects to brokers

// GOOD — it's a service (infrastructure-dependent)
src/services/kafka.service.ts
```

> "this is a pure transformation — should be a formatter, not a helper"
> "this connects to infrastructure — it's a service, not a helper"

---

### C-17: Schema/Model naming — singular PascalCase, plural snake_case collections
**Severity:** WARNING | **Category:** Naming

Schema and model names should be singular PascalCase. Collection names should be plural snake_case.

```ts
// BAD
const UsersSchema = new Schema({ ... });
const usersModel = model('users', UsersSchema);

// GOOD
const UserSchema = new Schema({ ... });
const UserModel = model('User', UserSchema);
// collection name (auto or explicit): 'users' or 'user_profiles'

// BAD — plural model name
export const OrganizationsModel = model('Organizations', OrganizationsSchema);

// GOOD — singular model name
export const OrganizationModel = model('Organization', OrganizationSchema);
```

> "schema name should be singular — `UserSchema`, not `UsersSchema`"
> "model names are singular PascalCase, collection names are plural snake_case"

---

## Quick Reference

| ID | Rule | Severity |
|----|------|----------|
| C-01 | No `I` prefix on interfaces (unless project convention) | WARNING |
| C-02 | Avoid `any` | WARNING |
| C-03 | Descriptive variable names | WARNING |
| C-04 | Remove comments | WARNING |
| C-05 | Extract magic strings to constants | CRITICAL |
| C-06 | No new .js files | CRITICAL |
| C-07 | Import ordering and absolute paths | INFO |
| C-08 | Linebreak formatting — especially before `if` | WARNING |
| C-09 | Extract test setup to beforeEach | CRITICAL |
| C-10 | Reuse test data with mock/actual prefix | CRITICAL |
| C-11 | Rename generic `result` | WARNING |
| C-12 | Remove unnecessary test timeouts | WARNING |
| C-13 | Avoid try-catch — let errors propagate | WARNING |
| C-14 | Don't explicitly `return undefined` | WARNING |
| C-15 | `it.each` — 2-3 params max, no `if` inside | WARNING |
| C-16 | File type suffixes (formatter/helper/utils/service) | INFO |
| C-17 | Schema/Model singular PascalCase, collection plural snake_case | WARNING |
