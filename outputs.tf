# BIGIP MGMT IP
output "eip_for_BIGIP" {
  description = "EIP or Public address for the BIGIP"
  value       = aws_eip_association.bigip.public_ip
}
