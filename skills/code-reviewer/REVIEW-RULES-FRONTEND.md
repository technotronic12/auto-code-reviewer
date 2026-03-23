# Frontend Review Rules

Rules for reviewing React/TypeScript frontend code: components, hooks, MobX stores, Material-UI usage, and their tests.
Source: 322 comments by technotronic12 across 34 windward-ltd PRs.

> **Note:** Common rules (types, naming, cleanup, testing basics) are in `REVIEW-RULES-COMMON.md` — always load that file alongside this one.

---

## Component Structure

### R-01: Keep return statements stupid
**Severity:** CRITICAL | **Category:** Structure

Return statements must contain zero logic. Extract all conditionals, mappings, filters, and transformations to named variables above the return.

```tsx
// BAD
return (
  <div>
    {items.filter(i => i.active).map(i => (
      <Card key={i.id} title={i.name.toUpperCase()} />
    ))}
    {isLoading ? <Spinner /> : null}
  </div>
);

// GOOD
const activeItems = items.filter(item => item.active);
const loadingIndicator = isLoading ? <Spinner /> : null;

return (
  <div>
    {activeItems.map(item => <Card key={item.id} title={item.name.toUpperCase()} />)}
    {loadingIndicator}
  </div>
);
```

> "return should be a stupid return as possible"
> "In general, we try to minimize the logic in `return`. We want the logic to be visible before"
> "consider extracting it out of the return statement, it is better to see all logic above the return"

---

### R-02: Break long returns into smaller components
**Severity:** CRITICAL | **Category:** Structure

Long JSX returns (~40+ lines) must be split. Each sub-component gets its own file, interface, and test file.

```tsx
// BAD — 200-line return with inline forms, dialogs, tables
return (
  <div>
    <form>...</form>
    <Dialog>...</Dialog>
    <Table>...</Table>
  </div>
);

// GOOD — each section is its own component in its own file
return (
  <div>
    <AccountForm {...formProps} />
    <ConfirmDialog {...dialogProps} />
    <AccountTable {...tableProps} />
  </div>
);
```

> "this return is waaaaaay too long. Let's break it down to multiple components, each in own file (and own test file)"
> "if I want to edit one of the parts, I must read all of this long return to understand what and where to change"
> "too many returns within returns within returns"

---

### R-03: Each component in its own file
**Severity:** WARNING | **Category:** Structure

Components must live in their own files with their own interfaces and test files. A return-within-a-return is a signal that a sub-component should be extracted.

```
// BAD
src/components/DeleteOrganization/
  DeleteOrganization.tsx        // contains Form, Dialog, and Table inline

// GOOD
src/components/DeleteOrganization/
  DeleteOrganization.tsx
  DeleteOrganization.test.tsx
  components/
    DeleteOrganizationForm.tsx
    DeleteOrganizationForm.test.tsx
    ConfirmDialog.tsx
    ConfirmDialog.test.tsx
```

> "Let's move each component to own file and then update the tests"
> "Each component should have it's own interface (for props)"
> "as this is a return within a return, this indicates that this should have been a separate component"

---

### R-04: Group hook calls together
**Severity:** INFO | **Category:** Structure

All `useState`, `useEffect`, `useMemo`, and custom hooks should be grouped at the top of the component, before any logic.

> "please move all hook calls to the same place (if possible ofc)"

---

### R-05: Extract logic to named functions instead of comments
**Severity:** WARNING | **Category:** Structure

If you need a comment to explain logic, extract it to a function with a descriptive name instead.

```tsx
// BAD
// Check if form can be submitted
const canSubmit = !isLoading && name.length > 0 && selectedOrg !== null;

// GOOD
function canSubmitForm(): boolean {
  return !isLoading && name.length > 0 && selectedOrg !== null;
}
```

> "maybe this logic should be extracted to a function with a meaningful name rather than adding a comment?"

---

## Types & Naming

### R-06: Component return type is JSX.Element
**Severity:** WARNING | **Category:** Types

All functional components must have `JSX.Element` as their return type.

```tsx
// BAD
export default function UserProfile() { ... }

// GOOD
export default function UserProfile(): JSX.Element { ... }
```

> "return type of all components is JSX.Element"
> "let's add return types everywhere, I think we use JSX.Element"

---

### R-07: Extract inline types to interfaces
**Severity:** WARNING | **Category:** Types

Don't use inline object types. Extract to named interfaces. This applies to component props and test helper function parameters. Interface names must be specific — `Props` alone is too generic; name it after the component: `OrganizationFieldProps`, `StatusBadgeProps`, etc. (easier to search, clearer ownership).

```tsx
// BAD — inline type
function StatusBadge({ disabled, reason }: { disabled: boolean; reason: string }) { ... }

// BAD — generic Props name
interface Props { disabled: boolean; reason: string; }

// BAD — test helper inline type
function renderField({ record, isLoading }: { record: Record<string, unknown>; isLoading: boolean }) { ... }

// GOOD
interface StatusBadgeProps {
  disabled: boolean;
  reason: string;
}
function StatusBadge({ disabled, reason }: StatusBadgeProps): JSX.Element { ... }

// GOOD — test helper
interface RenderFieldParams {
  record: Record<string, unknown>;
  isLoading: boolean;
}
function renderField({ record, isLoading }: RenderFieldParams): void { ... }
```

> "we should create interfaces and not use these types inline"
> "let's extract `{ disabled: boolean; reason: string }` to an interface"
> "OrganizationFieldProps (easier to search later if needed)"

---

### R-08: Prefer Type[] over Array\<Type\>
**Severity:** INFO | **Category:** Types

Use the shorthand array syntax.

```ts
// BAD
const items: Array<Item> = [];

// GOOD
const items: Item[] = [];
```

> "we usually do Type[] instead of Array\<Type\>"

---

### R-09: Descriptive variable names for state
**Severity:** WARNING | **Category:** Naming

Boolean state should describe what it tracks. Avoid generic names like `loading` or `loading2`.

```tsx
// BAD
const [loading, setLoading] = useState(false);
const [loading2, setLoading2] = useState(false);

// GOOD
const [isLoadingMongoOrganizations, setIsLoadingMongoOrganizations] = useState(false);
const [isLoadingFronteggOrganizations, setIsLoadingFronteggOrganizations] = useState(false);
```

> "isLoadingMongoOrganizations"
> "isLoadingFronteggOrganizations"

---

### R-10: File and folder naming
**Severity:** WARNING | **Category:** Naming

Component files and folders: `PascalCase`. Utility files: `kebab-case`. Remove redundant suffixes like "Field" from component names.

```
// BAD
src/components/fronteggAccounts/     // lowercase
AddressFields.tsx                     // redundant "Fields" suffix

// GOOD
src/components/FronteggAccounts/     // PascalCase
Address.tsx                           // clean name
```

> "component names (and folders) should start with a capital letter"
> "I think we can remove the Fields/Field suffix from all components"

---

## Code Cleanup

### R-11: Prefer async/await over .then()
**Severity:** INFO | **Category:** Cleanup

Use async/await instead of .then() chains. In hooks, use useEffect with an inner async function.

```tsx
// BAD
useEffect(() => {
  fetchData().then(data => setData(data));
}, []);

// GOOD
useEffect(() => {
  async function loadData(): Promise<void> {
    const data = await fetchData();
    setData(data);
  }
  loadData();
}, []);
```

> "I think you can use a `useEffect` so it will be async... then the code will look much better than this `.then` syntax"
> "async await maybe instead of an old style promise?"

---

### R-12: Question unnecessary hooks
**Severity:** INFO | **Category:** Cleanup

Question `useMemo`, `useCallback`, and other optimization hooks when there's no clear performance benefit.

> "why do you need useMemo here?"

---

## Testing

### R-13: Use data-testid for selectors
**Severity:** WARNING | **Category:** Testing

Use `data-testid` attributes for test selectors. Store test IDs as constants.

```tsx
// Component
<Button data-testid={TEST_IDS.SUBMIT_BUTTON}>Submit</Button>

// Test
const submitButton = screen.getByTestId(TEST_IDS.SUBMIT_BUTTON);
```

> "we usually use data-testid for this purpose"
> "let's use data-testid everywhere. also, please use a constant for it"

---

### R-14: Don't test native/third-party components
**Severity:** WARNING | **Category:** Testing

Don't test that MUI inputs store values or that React hooks work. Test YOUR logic only.

```tsx
// BAD — testing native input behavior
fireEvent.change(input, { target: { value: 'test' } });
expect(input.value).toBe('test');

// GOOD — test your logic's effect on the UI
fireEvent.click(submitButton);
expect(mockOnSubmit).toHaveBeenCalledWith(expectedData);
```

> "this test is redundant, you are testing here the actual input implementation (which we didn't implement)"
> "no need to test native components we use, if we didn't implement them we should assume they work"

---

### R-15: Wrap state changes in act()
**Severity:** WARNING | **Category:** Testing

Every action that alters component state in tests must be wrapped in `act()`.

> "shouldn't this be wrapped in `act`? please run all of your tests and make sure that we don't have the 'wrap in act' warning"

---

### R-16: Don't return render result unless used
**Severity:** INFO | **Category:** Testing

If you're not using the return value of `render()`, don't assign it or return it. This applies both to direct calls and to helper functions — if no caller uses the return value, the helper should not return it.

```tsx
// BAD — assigning unused result
const result = render(<Component />);

// BAD — helper returns render result but no caller uses it
function renderComponent(props: Props) {
  return render(<Component {...props} />);
}
renderComponent(props); // return value discarded

// GOOD
render(<Component />);

// GOOD — helper with no return
function renderComponent(props: Props): void {
  render(<Component {...props} />);
}
```

> "I don't think you should return the render result unless you use it"
> "not sure we actually need to return the render result"

---

### R-17: No redundant return types on test callbacks
**Severity:** INFO | **Category:** Testing

Don't add return types to `beforeEach`, `act`, or `it` callbacks — they're redundant.

> "the return types on `before each`, `act`, and, `it` are redundant"

---

### R-18: Tests shouldn't be async unless needed
**Severity:** INFO | **Category:** Testing

Only mark tests as `async` if they actually await something.

> "it shouldn't be async"
> "no need to be async"

---

## Quick Reference

| ID | Rule | Severity |
|----|------|----------|
| R-01 | Keep return statements stupid | CRITICAL |
| R-02 | Break long returns into components | CRITICAL |
| R-03 | Each component in its own file | WARNING |
| R-04 | Group hook calls together | INFO |
| R-05 | Extract logic to named functions | WARNING |
| R-06 | Component return type: JSX.Element | WARNING |
| R-07 | Extract inline types to interfaces | WARNING |
| R-08 | Prefer Type[] over Array\<Type\> | INFO |
| R-09 | Descriptive variable names for state | WARNING |
| R-10 | File and folder naming | WARNING |
| R-11 | Prefer async/await over .then() | INFO |
| R-12 | Question unnecessary hooks | INFO |
| R-13 | Use data-testid for selectors | WARNING |
| R-14 | Don't test native components | WARNING |
| R-15 | Wrap state changes in act() | WARNING |
| R-16 | Don't return render result unless used | INFO |
| R-17 | No redundant return types on callbacks | INFO |
| R-18 | Tests shouldn't be async unless needed | INFO |

> See also: **REVIEW-RULES-COMMON.md** for C-01 through C-12 (types, naming, cleanup, testing basics)
