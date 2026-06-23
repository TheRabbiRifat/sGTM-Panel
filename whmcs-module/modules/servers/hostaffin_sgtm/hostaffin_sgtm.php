<?php
/**
 * Hostaffin sGTM Hosting Platform — WHMCS Server Module
 *
 * @package    Hostaffin_sGTM
 * @author     Hostaffin Ltd.
 * @copyright  Copyright (c) 2026 Hostaffin Ltd.
 * @license    Proprietary
 * @link       https://hostaffin.com
 */

if (!defined('WHMCS')) {
    die('Access Denied');
}

require_once __DIR__ . '/lib/ApiClient.php';
require_once __DIR__ . '/lib/Hooks.php';

/**
 * Module metadata.
 */
function hostaffin_sgtm_MetaData()
{
    return [
        'DisplayName'    => 'Hostaffin sGTM Hosting',
        'APIVersion'     => '1.1',
        'RequiresServer' => false,
        'DefaultNonSSLPort'  => 80,
        'DefaultSSLPort'     => 443,
    ];
}

/**
 * Configurable options for WHMCS products.
 *
 * @return array
 */
function hostaffin_sgtm_ConfigOptions()
{
    return [
        'plan_slug' => [
            'FriendlyName' => 'Plan',
            'Type'         => 'dropdown',
            'Options'      => 'starter,Starter;growth,Growth;agency,Agency',
            'Description'  => 'Internal plan slug',
            'Default'      => 'starter',
        ],
        'edge_hostname' => [
            'FriendlyName' => 'Edge Hostname (read-only)',
            'Type'         => 'text',
            'Description'  => 'Auto-assigned after provisioning',
            'Size'         => 40,
            'ReadOnly'     => true,
        ],
    ];
}

/**
 * CreateAccount — invoked when the customer completes checkout.
 *
 * @param array $params
 * @return string "success" or error string
 */
function hostaffin_sgtm_CreateAccount($params)
{
    try {
        $client = Hostaffin_ApiClient::fromModuleParams($params);

        $planSlug = $params['configoption1'] ?? 'starter';

        $resp = $client->post('/api/services', [
            'whmcs_service_id' => (int) $params['serviceid'],
            'whmcs_client_id'  => (int) $params['userid'],
            'plan_slug'        => $planSlug,
            'domain'           => $params['domain'] ?? '',
        ]);

        if (!in_array($resp['status'] ?? '', ['pending', 'active'], true)) {
            return "Provisioning failed: " . ($resp['error']['message'] ?? 'unknown');
        }

        // Stash the edge hostname in the custom field for display
        if (!empty($resp['edge_hostname'])) {
            Hostaffin_Hooks::setServiceCustomField($params['serviceid'], 'edge_hostname', $resp['edge_hostname']);
        }
        Hostaffin_Hooks::setServiceCustomField($params['serviceid'], 'service_id', $resp['id'] ?? '');
        Hostaffin_Hooks::setServiceCustomField($params['serviceid'], 'plan_slug', $planSlug);

        Hostaffin_Hooks::logActivity($params['pid'], "Service #{$params['serviceid']} created via Hostaffin sGTM");

        return 'success';
    } catch (Throwable $e) {
        Hostaffin_Hooks::logActivity(0, "Hostaffin CreateAccount error: " . $e->getMessage());
        return $e->getMessage();
    }
}

/**
 * SuspendAccount — invoked by WHMCS on overdue/cancellation.
 */
function hostaffin_sgtm_SuspendAccount($params)
{
    try {
        $client = Hostaffin_ApiClient::fromModuleParams($params);
        $sid = Hostaffin_Hooks::getServiceCustomField($params['serviceid'], 'service_id');
        if ($sid) {
            $client->post("/api/services/{$sid}/suspend");
        }
        return 'success';
    } catch (Throwable $e) {
        return $e->getMessage();
    }
}

/**
 * UnsuspendAccount — invoked when customer pays the overdue invoice.
 */
function hostaffin_sgtm_UnsuspendAccount($params)
{
    try {
        $client = Hostaffin_ApiClient::fromModuleParams($params);
        $sid = Hostaffin_Hooks::getServiceCustomField($params['serviceid'], 'service_id');
        if ($sid) {
            $client->post("/api/services/{$sid}/unsuspend");
        }
        return 'success';
    } catch (Throwable $e) {
        return $e->getMessage();
    }
}

/**
 * TerminateAccount — invoked on cancellation.
 */
function hostaffin_sgtm_TerminateAccount($params)
{
    try {
        $client = Hostaffin_ApiClient::fromModuleParams($params);
        $sid = Hostaffin_Hooks::getServiceCustomField($params['serviceid'], 'service_id');
        if ($sid) {
            $client->delete("/api/services/{$sid}");
        }
        return 'success';
    } catch (Throwable $e) {
        return $e->getMessage();
    }
}

/**
 * ChangePackage — invoked on upgrade/downgrade.
 */
function hostaffin_sgtm_ChangePackage($params)
{
    try {
        $client = Hostaffin_ApiClient::fromModuleParams($params);
        $sid = Hostaffin_Hooks::getServiceCustomField($params['serviceid'], 'service_id');
        $planSlug = $params['configoption1'] ?? 'starter';
        if ($sid) {
            $client->post("/api/services/{$sid}/upgrade", [
                'plan_slug' => $planSlug,
            ]);
        }
        Hostaffin_Hooks::setServiceCustomField($params['serviceid'], 'plan_slug', $planSlug);
        return 'success';
    } catch (Throwable $e) {
        return $e->getMessage();
    }
}

/**
 * ClientAreaCustomButtonArray — adds buttons in the WHMCS client area.
 */
function hostaffin_sgtm_ClientAreaCustomButtonArray()
{
    return [
        'Restart Container' => 'restart',
        'Add Custom Domain' => 'addDomain',
        'Verify DNS'        => 'verifyDomain',
        'Upgrade Plan'      => 'upgrade',
        'View Loader'       => 'viewLoader',
        'View Cookie Extensions' => 'viewCookies',
    ];
}

/**
 * ClientAreaOutput — renders the custom panel HTML.
 */
function hostaffin_sgtm_ClientAreaOutput($params)
{
    $serviceId = Hostaffin_Hooks::getServiceCustomField($params['serviceid'], 'service_id');
    if (!$serviceId) {
        return '<div class="alert alert-warning">Service is not yet provisioned.</div>';
    }

    try {
        $client = Hostaffin_ApiClient::fromModuleParams($params);
        $service = $client->get("/api/services/{$serviceId}");
        $usage   = $client->get("/api/services/{$serviceId}/usage");
        $loaders = $client->get("/api/services/{$serviceId}/loaders");
        $cookies = $client->get("/api/services/{$serviceId}/cookie-extensions");
        $domains = $client->get("/api/services/{$serviceId}/domains");
    } catch (Throwable $e) {
        return '<div class="alert alert-danger">Could not load service data: ' . htmlspecialchars($e->getMessage()) . '</div>';
    }

    $tpl = __DIR__ . '/templates/clientarea.tpl';
    if (!file_exists($tpl)) {
        $tpl = __DIR__ . '/clientarea.tpl';
    }
    $vars = [
        'service'    => $service,
        'usage'      => $usage,
        'loaders'    => $loaders['items'] ?? [],
        'cookies'    => $cookies['items'] ?? [],
        'domains'    => $domains['items'] ?? [],
        'service_id' => $serviceId,
    ];
    return Hostaffin_Hooks::render($tpl, $vars);
}

/**
 * AdminCustomButtonArray — adds admin-only actions.
 */
function hostaffin_sgtm_AdminCustomButtonArray()
{
    return [
        'Force Restart'  => 'forceRestart',
        'Re-verify'      => 'reverify',
        'View Raw JSON'  => 'viewJson',
    ];
}