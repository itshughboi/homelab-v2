resource "unifi_firewall_rule" "rules" {
  for_each = local.firewall_rules

  name       = each.key
  action     = each.value.action
  ruleset    = "LAN_IN"
  rule_index = each.value.order

  protocol = each.value.proto
  dst_port = each.value.ports

  src_network_id = unifi_network.production[each.value.source].id
  dst_network_id = unifi_network.production[each.value.dest].id

  depends_on = [unifi_network.production]
}

resource "unifi_firewall_rule" "lan_established" {
  name       = "Allow established/related"
  action     = "accept"
  ruleset    = "LAN_IN"
  rule_index = 100

  state_established = true
  state_related     = true
}
