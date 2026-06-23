<?php
/**
 * Helper utilities used by the WHMCS module.
 */

class Hostaffin_Hooks
{
    /**
     * Returns a custom field value (or empty string).
     */
    public static function getServiceCustomField(int $serviceId, string $field): string
    {
        $row = Capsule::table('tblcustomfieldsvalues as v')
            ->join('tblcustomfields as f', 'f.id', '=', 'v.fieldid')
            ->where('v.relid', $serviceId)
            ->where('f.fieldname', $field)
            ->value('v.value');
        return $row !== null ? (string) $row : '';
    }

    /**
     * Sets a custom field value (creates the field if missing).
     */
    public static function setServiceCustomField(int $serviceId, string $field, string $value): void
    {
        $fieldId = Capsule::table('tblcustomfields')->where('fieldname', $field)->value('id');
        if (!$fieldId) {
            $fieldId = Capsule::table('tblcustomfields')->insertGetId([
                'type'       => 'product',
                'relid'      => 0,
                'fieldname'  => $field,
                'fieldtype'  => 'text',
                'description'=> 'Hostaffin sGTM — ' . $field,
                'regexpr'    => '',
                'adminonly'  => 'on',
                'required'   => '',
                'showorder'  => '',
                'showinvoice'=> '',
                'sortorder'  => 0,
            ]);
        }
        $existing = Capsule::table('tblcustomfieldsvalues')
            ->where('relid', $serviceId)
            ->where('fieldid', $fieldId)
            ->value('id');
        if ($existing) {
            Capsule::table('tblcustomfieldsvalues')
                ->where('id', $existing)
                ->update(['value' => $value]);
        } else {
            Capsule::table('tblcustomfieldsvalues')->insert([
                'relid'   => $serviceId,
                'fieldid' => $fieldId,
                'value'   => $value,
            ]);
        }
    }

    public static function logActivity(int $serviceId, string $message): void
    {
        if (function_exists('logActivity')) {
            logActivity($message);
        }
    }

    /**
     * Very small template renderer (no third-party deps).
     *
     * Replaces {{var}} with $vars['var'] (escaped).
     */
    public static function render(string $template, array $vars): string
    {
        if (!is_readable($template)) {
            return '';
        }
        $src = file_get_contents($template);
        $out = preg_replace_callback('/\{\{\s*([a-zA-Z0-9_\.]+)\s*\}\}/', function ($m) use ($vars) {
            $key = $m[1];
            $val = $vars[$key] ?? '';
            if (is_scalar($val) || is_null($val)) {
                return htmlspecialchars((string) $val, ENT_QUOTES, 'UTF-8');
            }
            return htmlspecialchars(json_encode($val), ENT_QUOTES, 'UTF-8');
        }, $src);
        return (string) $out;
    }
}