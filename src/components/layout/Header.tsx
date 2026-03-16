import { OrganizationSwitcher, UserButton } from '@clerk/clerk-react';

export function Header() {
  return (
    <header className="flex h-14 items-center justify-between border-b px-4 md:px-6">
      <div className="md:hidden text-lg font-semibold">Art Inventory</div>
      <div className="hidden md:block" />
      <div className="flex items-center gap-4">
        <OrganizationSwitcher
          appearance={{
            elements: {
              rootBox: 'flex items-center',
              organizationSwitcherTrigger: 'px-2 py-1 rounded-md border',
            },
          }}
        />
        <UserButton afterSignOutUrl="/sign-in" />
      </div>
    </header>
  );
}
