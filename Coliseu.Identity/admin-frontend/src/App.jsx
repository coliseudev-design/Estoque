import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';

/* Pages */
import Login from './pages/auth/Login';
import Register from './pages/auth/Register';

/* Dashboard Layout */
import DashboardLayout from './components/layout/DashboardLayout';
import DashboardHome from './pages/dashboard/Dashboard';
import CompanyList from './pages/companies/CompanyList';
import CompanyDetails from './pages/companies/CompanyDetails';
import Audit from './pages/audit/Audit';
import Settings from './pages/settings/Settings';
import SalesApiManager from './pages/salesapi/SalesApiManager';
import SalesReport from './pages/salesapi/SalesReport';
import KpiDashboard from './pages/salesapi/KpiDashboard';
import TenantManager from './pages/salesapi/TenantManager';
import AuditTrail from './pages/salesapi/AuditTrail';
import WebhookManager from './pages/salesapi/WebhookManager';
import UserManagement from './pages/settings/UserManagement';
import Requests from './pages/requests/Requests';
import Partners from './pages/partners/Partners';

function App() {
  return (
    <BrowserRouter>
      <Routes>
        {/* Public Routes */}
        <Route path="/" element={<Login />} />
        <Route path="/register" element={<Navigate to="/" replace />} />

        {/* Protected Dashboard Routes */}
        <Route path="/dashboard" element={<DashboardLayout />}>
          <Route index element={<Navigate to="/dashboard/home" replace />} />
          <Route path="home" element={<DashboardHome />} />
          <Route path="companies" element={<CompanyList />} />
          <Route path="companies/:id" element={<CompanyDetails />} />
          <Route path="requests" element={<Requests />} />
          <Route path="partners" element={<Partners />} />
          <Route path="audit" element={<Audit />} />
          <Route path="sales-api" element={<SalesApiManager />} />
          <Route path="sales-report" element={<SalesReport />} />
          <Route path="kpi" element={<KpiDashboard />} />
          <Route path="tenants" element={<TenantManager />} />
          <Route path="audit-trail" element={<AuditTrail />} />
          <Route path="webhooks" element={<WebhookManager />} />
          <Route path="users" element={<UserManagement />} />
          <Route path="settings" element={<Settings />} />
        </Route>

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;
