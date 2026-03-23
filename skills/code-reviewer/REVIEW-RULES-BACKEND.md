# Backend Review Rules

Rules for reviewing Node.js/TypeScript backend code: GraphQL services, DAL layers, service files, utilities, and their tests.
Source: 322 comments by technotronic12 across 34 windward-ltd PRs.

> **Note:** Common rules (types, naming, cleanup, testing basics) are in `REVIEW-RULES-COMMON.md` — always load that file alongside this one.

---

## Structure & Decomposition

### R-01: Each step should be a function
**Severity:** CRITICAL | **Category:** Structure

Sequential operations in a method should each be a named function. Validation chains, data transformations, and multi-step processes must be decomposed.

```ts
// BAD
async create(request) {
  if (!request.name) throw new Error('Missing name');
  if (await exists(request.name)) throw new Error('Already exists');
  const metadata = { ...request, createdAt: new Date() };
  const result = await service.create(metadata);
  await service.assignPlans(result.id, request.plans);
  return result;
}

// GOOD
async create(request) {
  validateAccountRequest(request);
  await validateAccountDoesNotExist(request.name);
  const metadata = buildAccountMetadata(request);
  const account = await service.create(metadata);
  await assignPlansToAccount(account.id, request.plans);
  return account;
}
```

> "basically, each step here should be a function"
> "this and the following condition can be extracted to `validateAccountDoesNotExist` or similar"

---

### R-02: One function, one responsibility
**Severity:** WARNING | **Category:** Structure

If a function name contains "And", it likely does two things. Functions that do too many things should be split. Also: a function must only do what its name promises — if you find side effects (caching, state mutations, logging unrelated to the function's purpose) tucked inside a well-named method, extract them.

```ts
// BAD — "And" in the name
async function createAccountAndAssignPlans(data) { ... }

// GOOD
async function createAccount(data) { ... }
async function assignPlans(accountId, plans) { ... }

// BAD — caching app config inside a client initializer is unrelated to client init
async function #initializeFronteggClient(instanceIdentifier) {
  const { clientId, apiKey, applications } = await secrets.getJsonKeyValue(...);
  this.instanceApplications.set(instanceIdentifier, applications); // unrelated side effect
  const authenticator = new FronteggAuthenticator();
  await authenticator.init(clientId, apiKey);
}

// GOOD — separate the concerns
async function #initializeFronteggClient(instanceIdentifier) {
  const { clientId, apiKey } = await this.#loadInstanceConfig(instanceIdentifier);
  const authenticator = new FronteggAuthenticator();
  await authenticator.init(clientId, apiKey);
}
```

> "usually when you have And (not always but...) in a function name, it means it should be two functions :)"
> "this method does too many things"
> "I don't think that it should happen inside initializeFronteggClient as it is not related to the client at all... We are saving here some info that we will need to use in a different flow."

---

### R-03: No self-invoking functions
**Severity:** INFO | **Category:** Structure

Self-invoking (IIFE) functions are unclear. Extract to a named function.

```ts
// BAD
const result = (() => { if (condition) return a; return b; })();

// GOOD
const result = determineValue(condition);
```

> "self invoking function is complicated and unclear, we only use it when we must"

---

### R-04: Reuse duplicate logic across similar flows
**Severity:** WARNING | **Category:** Structure

If the same chain of calls appears in multiple methods (create/update, share/edit, etc.), extract to a shared function. This applies broadly — not just create/update, but any pair of flows with overlapping logic.

> "seems that you have this chain of calls (plans, apps, metadata) both in the create and update functions. it means they can be probably wrapped in a function and reused."
> "This function looks very similar to the changeACL flow, why can't we reuse things here and duplicating this logic?"

---

### R-05: Keep return statements clean — extract inline expressions to named variables
**Severity:** WARNING | **Category:** Structure

Extract logic out of return statements into named variables above the return. This also applies to inline `.get()` calls, complex boolean conditions, and map/filter chains — anything whose intent isn't immediately clear from reading the expression. A well-named variable acts as documentation.

```ts
// BAD — logic buried in return
return organizations.filter(o => o.active).sort((a, b) => a.name.localeCompare(b.name)).slice(0, limit);

// GOOD — extracted to named variables
const activeOrganizations = organizations.filter(o => o.active);
const sortedOrganizations = activeOrganizations.sort((first, second) => first.name.localeCompare(second.name));
return sortedOrganizations.slice(0, limit);

// BAD — .get() result used inline, unclear what it returns
accessors: voisAccessorsMap.get(voiId.toString()),

// GOOD — extracted to a named variable
const voiAccessors = voisAccessorsMap.get(voiId.toString());
// ...
accessors: voiAccessors,

// BAD — complex condition inline
if (!accessors.length || (!projectVois.length && !projectPolygons.length)) {

// GOOD — extracted with descriptive name
const hasNoAccessorsOrResources = !accessors.length || (!projectVois.length && !projectPolygons.length);
if (hasNoAccessorsOrResources) {

// BAD — complex boolean expression in return
return (
  !!existingPermissions.get(`${resourceId}:${accessorUser.organizationId}`) ||
  accessorUser.groupIds.some(groupId => existingPermissions.get(`${resourceId}:${groupId}`))
);

// GOOD — each condition extracted
const hasOrgAccess = !!existingPermissions.get(`${resourceId}:${accessorUser.organizationId}`);
const hasGroupAccess = accessorUser.groupIds.some(groupId => existingPermissions.get(`${resourceId}:${groupId}`));
return hasOrgAccess || hasGroupAccess;
```

> "let's try to eliminate logic from the `return` statement"
> "extract to a variable so it will be clear what is the result of it"
> "extract the two conditions to a variable so it will be clear what you are testing here, both expressions are complex. having a good name will allow me not to check the actual expressions to understand what the code does."
> "extract the condition into a clear variable"

---

## Architecture

### R-06: Service layer separation — no cross-domain coupling
**Severity:** CRITICAL | **Category:** Architecture

Services must not be aware of their callers. A core service (e.g., `frontegg.service`) must not import or reference backoffice-specific logic. The calling layer (CRUD controller) orchestrates.

**Flow:** `CRUD Controller → Service → DAL/Model`

```ts
// BAD — frontegg.service.ts importing backoffice types
import { BackofficeConfig } from '/routes/backoffice/types';
async createAccountFromBackoffice(config: BackofficeConfig) { ... }

// GOOD — frontegg.service.ts is generic
async createAccount(params: CreateAccountParams) { ... }

// GOOD — orchestration lives in the controller
// frontegg-accounts-crud.controller.ts
async create(request) {
  const account = await FronteggService.createAccount(params);
  await FronteggService.assignPlans(account.id, plans);
}
```

> "I don't think that frontegg.service should be familiar with the backoffice, it is our gateway to the Frontegg API. This creates un-needed coupling"
> "The flow should be -> CRUD -> FronteggService -> InstanceMappingService -> Model (DB)"

---

### R-07: Use DAL layer — don't access models or DAL internals directly
**Severity:** CRITICAL | **Category:** Architecture

Never import/use a Mongoose model directly from a service or controller. Always go through the DAL. Each database should be accessed by only one service. Additionally, don't reach into DAL internal members from helpers or services — if you need a capability, expose it as a proper method on the DAL.

```ts
// BAD — accessing model directly
import OrganizationModel from '/model/organization';
const org = await OrganizationModel.findById(id);

// BAD — reaching into DAL internals
const hasAccess = await SavedQueryDAL.savedQueryACL.hasPermission({ ... });

// GOOD — go through the DAL's public API
import OrganizationDAL from '/dal/organization.dal';
const org = await OrganizationDAL.getById(id);

// GOOD — DAL exposes the capability as a method
const hasAccess = await SavedQueryDAL.hasPermission({ ... });
```

> "we should indeed try not to access the model directly (DAL is a good design pattern)"
> "DALs shouldn't be familiar with each other. It is a code smell"
> "we shouldn't access dal members directly. Please create proper function for it"

---

### R-08: Extract pure functions out of classes — validators, mappers, helpers
**Severity:** WARNING | **Category:** Architecture

If a static method doesn't use `this`, extract it from the class into a separate utility/mapper file. This applies to validators, data transformers, mappers, and any pure logic sitting inside a DAL or service class. Benefits: the function becomes independently testable, can be typed properly in TypeScript, and is no longer hidden behind `private`/`#`.

```ts
// BAD — validator as static method on service class
class FronteggService {
  static validateAccount(data) { ... }
}

// BAD — pure mapper logic hidden as private method in DAL
class SavedQueryDAL {
  static #buildExistingPermissionsMap(vois, polygons) { ... }  // pure function, no `this`
}

// GOOD — separate validator file with its own tests
// validations/account.validator.ts
export function validateAccount(data: AccountData): void { ... }

// GOOD — mapper extracted to utility file, testable, typed
// utils/permissions.mapper.ts
export function buildPermissionsByResourceAndAccessor(vois: VOI[], polygons: Polygon[]): Map<string, string> { ... }
```

> "if you don't use `this` in a validator, I think it is better to extract it out of the service code"
> "validator should have a tests file, then, you can mock it instead of mocking the model everywhere"
> "if it is a helper that doesn't use `this`, consider extracting to some mapper file and use it (and not as part of the dal)"
> "these functions are complex and without types (as it is not TS) and tests that show input and output it is impossible to clearly understand what is going on... if you extract them to a util, it will be TS, it will not be private so you can add unit tests to them"

---

### R-09: Move enums/constants/errors closer to usage
**Severity:** INFO | **Category:** Architecture

Don't dump unrelated enums, constants, or error strings into a single `common/` file. Move them to the module that uses them. This applies to `common/enums.ts`, `common/errors.ts`, `common/constants.ts` — any shared file that becomes a dumping ground for unrelated content.

```ts
// BAD — service-specific errors in a shared common file
// src/common/errors.ts
export const ERROR_CREATE_DELETE_ORGANIZATION_MISSING_REQUIRED_FIELDS = '...';
export const ERROR_SOME_OTHER_SERVICE_THING = '...';  // unrelated

// GOOD — errors live next to the service that uses them
// src/services/delete-organization/errors.ts
export const ERROR_MISSING_REQUIRED_FIELDS = '...';
export const ERROR_ALREADY_IN_PROGRESS = '...';
```

> "let's not add more things to this common enum, it makes no sense to have a single file for enums which don't relate to each other. I suggest we move this closer to the implementation, where it is being used."
> "is it actually common? I think that specific errors file should sit closer to where it is being used. keeping it in 'common' will just create a garbage strings file with unrelated content."

---

### R-10: Question hardcoded values and defaults
**Severity:** WARNING | **Category:** Architecture

When you see a hardcoded boolean, number, or string — ask why that value was chosen and whether it should be configurable.

> "yesterday we had 300 messages, why did you choose 500?"
> "are you sure we want to default to `true`?"
> "shouldn't this be configurable? why false?"

---

## Types & Naming

### R-11: Extract inline types to interfaces
**Severity:** WARNING | **Category:** Types

Don't use inline object types. Extract to a named interface. Use `interface` over `type` (types only for unions).

```ts
// BAD
function getConfig(options: { timeout: number; retries: number }): void { ... }

// GOOD
interface GetConfigOptions {
  timeout: number;
  retries: number;
}
function getConfig(options: GetConfigOptions): void { ... }
```

> "we should create interfaces and not use these types inline"
> "better use interface for these, we should use type for complex/union types"

---

### R-12: Add return types and parameter types to all functions
**Severity:** WARNING | **Category:** Types

Every function must have an explicit return type (`void` for functions that return nothing) and explicit parameter types. When suggesting type fixes, always follow R-11: use named interfaces for object types, never inline types. Use `type` only for unions or complex types.

```ts
// BAD — missing types
async function getUser(id: string) { ... }

// BAD — inline type on parameter (violates R-11)
function validate(request: { status: string } | null): void { ... }

// GOOD — named interface + explicit return type
interface DeleteOrganizationRequest {
  status: string;
}
function validate(request: DeleteOrganizationRequest | null): void { ... }

// GOOD — simple types are fine inline
async function getUser(id: string): Promise<User | null> { ... }
```

> "please add return types to functions"
> "add return type"
> "extract to an interface"

---

### R-13: File naming conventions
**Severity:** WARNING | **Category:** Naming

Backend/utils files: `kebab-case.ts`. UPPER_CASE only for actual constants, not functions.

```
// BAD
src/services/deleteMongoOrganization.service.js

// GOOD
src/services/organization-deletion.service.ts
```

> "backend/utils code should be kebab-case"
> "UPPER_CASE should only be used for actual constants. Functions should follow the regular camelCase syntax"

---

## Testing

### R-14: Use describe blocks for test organization
**Severity:** WARNING | **Category:** Testing

Group tests by behavior: success vs error cases.

```ts
describe('createUser', () => {
  describe('should succeed', () => { ... });
  describe('should throw', () => { ... });
});
```

> "consider wrapping the positive and negative in describes for easier navigation in tests"

---

### R-15: Mock and assert at the right abstraction level
**Severity:** CRITICAL | **Category:** Testing

Mock and assert at the same layer the production code depends on. Testing a service that uses a DAL? Mock the DAL, not the model it wraps. This applies to both mock setup AND `expect` assertions.

```ts
// BAD — production uses OrganizationDAL, but test spies on the model
jest.spyOn(OrganizationModel, 'getById').mockResolvedValue(...);
expect(OrganizationModel.getById).toHaveBeenCalledWith(id);

// GOOD — spy and assert on the same layer production code uses
jest.spyOn(OrganizationDAL, 'getById').mockResolvedValue(...);
expect(OrganizationDAL.getById).toHaveBeenCalledWith(id);
```

> "don't mock the model if we don't use it directly, mock the class that uses the model"
> "if you use the DAL don't use the model directly, you should do this assertion on the DAL"
> "too many mocks at this level"

---

### R-16: One assertion focus per test
**Severity:** INFO | **Category:** Testing

Many expectations in one test = split into multiple tests.

> "when you see you have many expectations in a single test, it usually means this test should be split"

---

### R-17: Don't mutate input parameters — prefer functional
**Severity:** WARNING | **Category:** Structure

Functions should not mutate their inputs. Return a new object instead. Mutating internal members or config objects is bug-prone and makes debugging harder.

```ts
// BAD — mutates the config object passed in
async function initCredentials(config: MSKConfig): Promise<void> {
  config.ssl = true;
  config.sasl = await getCredentials();
}

// GOOD — returns a new config
async function getConfigWithCredentials(config: MSKConfig): Promise<MSKConfig> {
  const credentials = await getCredentials();
  return { ...config, ssl: true, sasl: credentials };
}
```

> "let's use a more functional approach without sideEffects. mutating internal members is bug prone and a more functional architecture will allow a more robust solution and easier debugging."

---

### R-18: Use TypeScript `private`, not JS `#` private fields
**Severity:** INFO | **Category:** Types

Use the TypeScript `private` keyword for class members, not the JavaScript `#` private field syntax.

```ts
// BAD
class DeleteProjectResources {
  #models: Record<string, Model>;
}

// GOOD
class DeleteProjectResources {
  private models: Record<string, Model>;
}
```

> "no need to use `#`. we can use TS `private` annotation."

---

### R-20: Functions with >2 parameters — use object + interface
**Severity:** WARNING | **Category:** Types

Any function (or method) with more than 2 parameters must take a single options object instead. The shape of that object must be extracted to a named interface.

```ts
// BAD — 3 positional parameters
async function createGroupWithUsers(organization, instanceIdentifier, migratedFronteggUsersIds) { ... }

// GOOD — single object param + interface
interface CreateGroupWithUsersParams {
  organization: Organization;
  instanceIdentifier: InstanceIdentifierType;
  fronteggUsersIds: string[];
}
async function createGroupWithUsers({ organization, instanceIdentifier, fronteggUsersIds }: CreateGroupWithUsersParams) { ... }
```

> "when we have > 2 parameters let's convert it to an object, also, let's extract inline types"

---

### R-21: Don't abstract test code at the cost of clarity
**Severity:** WARNING | **Category:** Testing

Don't extract shared test logic into helper functions if doing so makes the test body opaque. Saving 2-3 lines of duplication is not worth making a test hard to read or debug. Helpers that mix spy setup, execution, and assertions inside a single function are hard to reason about.

```ts
// BAD — opaque helper, hard to debug when it fails
async function runTest(appFeatures, apps, expectedIds) {
  jest.spyOn(OrganizationModel, 'getById').mockResolvedValue({ appFeatures });
  jest.spyOn(AppModel, 'get').mockResolvedValue(apps);
  await migrator.migrate();
  expect(FronteggService.assignApplicationsToAccount).toHaveBeenCalledWith(
    expect.objectContaining({ applicationIds: expectedIds })
  );
}

// GOOD — spy setup in beforeEach, test body is readable
beforeEach(() => {
  jest.spyOn(OrganizationDAL, 'getById').mockResolvedValue({ appFeatures: mockAppFeatures });
  jest.spyOn(AppDAL, 'get').mockResolvedValue(mockApps);
});
it('assigns MARINT application', async () => {
  await migrator.migrate();
  expect(FronteggService.assignApplicationsToAccount).toHaveBeenCalledWith(
    expect.objectContaining({ applicationIds: [FronteggApplication.WINDWARD_MARINT_QA] })
  );
});
```

> "this is super not clear, saving code duplication cannot be 'paid' with complexity"
> "too complex"
> "why do you need this in runTest?"

---

### R-22: Mongoose interfaces — don't define both `_id` and `id`
**Severity:** WARNING | **Category:** Types

When defining TypeScript interfaces for Mongoose documents, don't include both `_id` and `id`. The standard is `_id` (the actual MongoDB field). The `id` virtual is added automatically by Mongoose (or the serialization library). Having both creates confusion and potential type mismatches (`_id` is `ObjectId`, `id` is typically `string`).

```ts
// BAD — both _id and id
export interface DeleteOrganization {
  _id?: Types.ObjectId;
  id: Types.ObjectId;       // confusing: is this string or ObjectId?
  organizationId: Types.ObjectId;
}

// GOOD — just _id
export interface DeleteOrganization {
  _id: Types.ObjectId;
  organizationId: Types.ObjectId;
}
```

> "I think you can drop one of them. If I remember correctly, the standard is _id but our sequelize library that we use makes sure that we have .id also. Let's verify?"

---

### R-19: Don't redundantly reset mocks
**Severity:** INFO | **Category:** Testing

Don't re-set mock implementations that are already the default. `jest.clearAllMocks()` only clears call history, not implementations.

```ts
// BAD — redundant, jest.fn() already returns undefined
beforeEach(() => {
  mockFetchEntities.mockResolvedValue(undefined);
  mockDeleteEntities.mockResolvedValue(undefined);
});

// GOOD — only reset when changing from a non-default implementation
beforeEach(() => {
  // jest.clearAllMocks() in afterEach handles call history
});
```

> "`mockFetchEntities.mockResolvedValue(undefined)` is redundant — `jest.clearAllMocks()` only clears call history, not implementations. The top-level mock already returns `undefined` by default."

---

### R-23: Pass only what's needed — don't pass whole objects when you only use one field
**Severity:** WARNING | **Category:** Structure

If a function only needs an ID from an object, pass the ID — not the whole object. Passing the full object hides the actual dependency and makes the function signature misleading.

```ts
// BAD — passes the full accessor object but only uses accessor.accessorId
static #accessorAlreadyHasAccess({ accessor, usersMap }) {
  const accessorUser = usersMap.get(accessor.accessorId);
  ...
}

// GOOD — passes only what's needed
static #accessorAlreadyHasAccess({ accessorId, usersMap }) {
  const accessorUser = usersMap.get(accessorId);
  ...
}
```

> "seems that you don't need the full accessor here no? only its id?"

---

### R-24: Question unnecessary mocks in tests
**Severity:** WARNING | **Category:** Testing

Every `jest.mock()` call should be justified. If the module being mocked isn't imported or used by the code under test, the mock is unnecessary noise that makes the test harder to understand and maintain.

```ts
// BAD — mocking a database module when the test only exercises pure logic
jest.mock('@ww/gql-base-service/lib/database', () => ({ ... }));  // not needed for this test

// GOOD — only mock what the code under test actually touches
```

> "why do you need to mock it?"

---

### R-25: Function name must match all its behaviors
**Severity:** WARNING | **Category:** Naming

If a function does more than its name suggests, either rename it to cover all behaviors or split it. A function called `validateQueryName` that also runs `assertValidQueryInput` (unrelated to the name) is confusing.

```ts
// BAD — name says "validate name" but also validates the query input
static async validateQueryName({ name, savedQuery, query, user, id }) {
  const trimmedName = name.trim();
  if (savedQuery.name !== trimmedName) {
    await SavedQueryHelper.assertValidSavedQuery(trimmedName, query, user, { ignoreId: id });
  } else {
    SavedQueryHelper.assertValidQueryInput(query);  // nothing to do with the name
  }
  return trimmedName;
}

// GOOD — either rename to cover both responsibilities or split
static async validateAndPrepareQueryUpdate({ name, savedQuery, query, user, id }) { ... }
// OR split into two focused functions
```

> "this is unclear, what are these two assertions? what does it mean that the savedQuery name is not the same as the trimmed name?"

---

## Quick Reference

| ID | Rule | Severity |
|----|------|----------|
| R-01 | Each step should be a function | CRITICAL |
| R-02 | One function, one responsibility | WARNING |
| R-03 | No self-invoking functions | INFO |
| R-04 | Reuse duplicate logic across create/update | WARNING |
| R-05 | Keep return statements clean — extract inline expressions | WARNING |
| R-06 | Service layer separation | CRITICAL |
| R-07 | Use DAL, don't access models or DAL internals directly | CRITICAL |
| R-08 | Extract pure functions out of classes | WARNING |
| R-09 | Move enums/constants/errors closer to usage | INFO |
| R-10 | Question hardcoded values | WARNING |
| R-11 | Extract inline types to interfaces | WARNING |
| R-12 | Add return types to all functions | WARNING |
| R-13 | File naming: kebab-case | WARNING |
| R-14 | Use describe blocks | WARNING |
| R-15 | Mock at right abstraction level | CRITICAL |
| R-16 | One assertion focus per test | INFO |
| R-17 | Don't mutate input parameters | WARNING |
| R-18 | Use TS `private`, not JS `#` | INFO |
| R-19 | Don't redundantly reset mocks | INFO |
| R-20 | Functions with >2 params → object + interface | WARNING |
| R-21 | Don't abstract test code at cost of clarity | WARNING |
| R-22 | Mongoose: don't define both `_id` and `id` | WARNING |
| R-23 | Pass only what's needed, not whole objects | WARNING |
| R-24 | Question unnecessary mocks | WARNING |
| R-25 | Function name must match all behaviors | WARNING |

> See also: **REVIEW-RULES-COMMON.md** for C-01 through C-17 (types, naming, cleanup, testing basics)
