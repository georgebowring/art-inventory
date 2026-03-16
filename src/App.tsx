import {
  ClerkProvider,
  SignedIn,
  SignedOut,
} from '@clerk/clerk-react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { AppLayout } from './components/layout/AppLayout';
import Dashboard from './pages/Dashboard';
import Artworks from './pages/Artworks';
import ArtworkDetail from './pages/ArtworkDetail';
import Artists from './pages/Artists';
import Contacts from './pages/Contacts';
import Transactions from './pages/Transactions';
import Locations from './pages/Locations';
import Exhibitions from './pages/Exhibitions';
import Documents from './pages/Documents';
import Settings from './pages/Settings';
import SignIn from './pages/SignIn';
import NotFound from './pages/NotFound';

const clerkPubKey = import.meta.env.VITE_CLERK_PUBLISHABLE_KEY;

function App() {
  return (
    <ClerkProvider publishableKey={clerkPubKey}>
      <BrowserRouter>
        <SignedOut>
          <SignIn />
        </SignedOut>
        <SignedIn>
          <Routes>
            <Route element={<AppLayout />}>
              <Route path="/" element={<Dashboard />} />
              <Route path="/artworks" element={<Artworks />} />
              <Route path="/artworks/:id" element={<ArtworkDetail />} />
              <Route path="/artists" element={<Artists />} />
              <Route path="/contacts" element={<Contacts />} />
              <Route path="/transactions" element={<Transactions />} />
              <Route path="/locations" element={<Locations />} />
              <Route path="/exhibitions" element={<Exhibitions />} />
              <Route path="/documents" element={<Documents />} />
              <Route path="/settings" element={<Settings />} />
              <Route path="*" element={<NotFound />} />
            </Route>
          </Routes>
        </SignedIn>
      </BrowserRouter>
    </ClerkProvider>
  );
}

export default App;
