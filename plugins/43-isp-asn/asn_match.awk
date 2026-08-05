# asn_match.awk — classify log lines into irancell / mci / other
# Usage:
#   awk -f asn_match.awk -v irancell_file=... -v mci_file=... [-v other_file=...] filtered.log
#
# Input log: time ip host status method "uri" bytes
# Output:
#   TOTAL  req  bytes
#   GROUP  name  req  bytes
#   IP     group  ip  req  bytes

function ip2int(ip,   a, n) {
  n = split(ip, a, ".")
  if (n != 4) return -1
  return ((a[1] * 16777216) + (a[2] * 65536) + (a[3] * 256) + a[4])
}

function cidr_to_range(cidr,   parts, ip, pfx, ipn, hosts, start, end, i) {
  split(cidr, parts, "/")
  ip = parts[1]
  pfx = parts[2] + 0
  if (pfx < 0 || pfx > 32) return
  ipn = ip2int(ip)
  if (ipn < 0) return
  if (pfx == 0) {
    start = 0
    end = 4294967295
  } else {
    hosts = 1
    for (i = 0; i < (32 - pfx); i++) hosts *= 2
    start = ipn - (ipn % hosts)
    if (start < 0) start = 0
    end = start + hosts - 1
  }
  nranges++
  r_start[nranges] = start
  r_end[nranges] = end
  r_group[nranges] = cur_group
}

function load_cidr_file(file, group,   line) {
  cur_group = group
  while ((getline line < file) > 0) {
    sub(/\r$/, "", line)
    if (line ~ /^[[:space:]]*$/) continue
    if (line ~ /^#/) continue
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    if (line ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/) {
      cidr_to_range(line)
    }
  }
  close(file)
}

function classify(ip,   ipn, i) {
  ipn = ip2int(ip)
  if (ipn < 0) return "other"
  if (ipn in cache) return cache[ipn]
  for (i = 1; i <= nranges; i++) {
    if (ipn >= r_start[i] && ipn <= r_end[i]) {
      cache[ipn] = r_group[i]
      return r_group[i]
    }
  }
  cache[ipn] = "other"
  return "other"
}

BEGIN {
  nranges = 0
  if (irancell_file != "") load_cidr_file(irancell_file, "irancell")
  if (mci_file != "") load_cidr_file(mci_file, "mci")
  if (other_file != "") load_cidr_file(other_file, "other")
}

{
  ip = $2
  bytes = $NF + 0
  if (index(ip, ":") > 0) g = "other"
  else g = classify(ip)
  req[g]++
  byt[g] += bytes
  ip_req[g SUBSEP ip]++
  ip_byt[g SUBSEP ip] += bytes
  total_req++
  total_byt += bytes
}

END {
  printf "TOTAL\t%d\t%d\n", total_req + 0, total_byt + 0
  for (g in req) {
    printf "GROUP\t%s\t%d\t%d\n", g, req[g], byt[g]
  }
  for (k in ip_req) {
    split(k, a, SUBSEP)
    printf "IP\t%s\t%s\t%d\t%d\n", a[1], a[2], ip_req[k], ip_byt[k]
  }
}
