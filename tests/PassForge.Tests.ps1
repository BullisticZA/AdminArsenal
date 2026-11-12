Import-Module $PSScriptRoot/../tools/passforge/PassForge.psm1 -Force
$ok = $true
function Check($name, $cond) { if ($cond) { "PASS $name" } else { "FAIL $name"; $script:ok = $false } }

$pw = New-PassForgePassword -Count 200 -Length 20
Check 'length 20'          (@($pw | Where-Object { $_.Password.Length -ne 20 }).Count -eq 0)
Check 'all classes present' (@($pw | Where-Object { $_.Password -cnotmatch '[a-z]' -or $_.Password -cnotmatch '[A-Z]' -or $_.Password -notmatch '\d' -or $_.Password -notmatch '[^a-zA-Z0-9]' }).Count -eq 0)
Check 'unique'             (@($pw.Password | Sort-Object -Unique).Count -eq 200)
$na = New-PassForgePassword -Count 200 -Length 30 -NoAmbiguous
Check 'no ambiguous chars' (@($na | Where-Object { $_.Password -cmatch '[Il1O0o|`''"]' }).Count -eq 0)
$ns = New-PassForgePassword -Count 50 -NoSymbols -NoDigits
Check 'letters only'       (@($ns | Where-Object { $_.Password -match '[^a-zA-Z]' }).Count -eq 0)
"sample: $($pw[0].Password)  bits=$($pw[0].EntropyBits) $($pw[0].Strength) crack=$($pw[0].CrackTime)"

# Distribution sanity: digits 0-9 drawn 100k times should each be ~10%
$counts = @{}; 1..20000 | ForEach-Object { $d = (& (Get-Module PassForge) { Get-PfRandomInt -Max 10 }); $counts[$d]++ }
$min = ($counts.Values | Measure-Object -Minimum).Minimum; $max = ($counts.Values | Measure-Object -Maximum).Maximum
Check "uniform RNG (min $min max $max of ~2000)" ($min -gt 1800 -and $max -lt 2200 -and $counts.Count -eq 10)

$pp = New-PassForgePassphrase -Count 50
$words = Get-Content $PSScriptRoot/../tools/passforge/eff_large_wordlist.txt
Check 'passphrase 6 list words' (@($pp | Where-Object { $p = $_.Passphrase -split '-'; $p.Count -ne 6 -or @($p | Where-Object { $_ -notin $words }).Count }).Count -eq 0)
$pp2 = New-PassForgePassphrase -Words 5 -Separator ' ' -Capitalize -AddNumber
Check 'capitalize + number' ($pp2.Passphrase -cmatch '^[A-Z]' -and $pp2.Passphrase -match '\d')
"sample: $($pp[0].Passphrase)  bits=$($pp[0].EntropyBits) $($pp[0].Strength)"
"sample: $($pp2.Passphrase)  bits=$($pp2.EntropyBits)"

foreach ($t in 'password','P@ssw0rd','aaaaaaaa','12345678abc','correct-horse-battery-staple', $pw[0].Password) {
  $m = ConvertTo-SecureString $t -AsPlainText -Force | Measure-PassForgeStrength
  "{0,-30} {1,6} {2,-9} {3}" -f $t, $m.EntropyBits, $m.Strength, $m.Notes
}
$m = ConvertTo-SecureString 'password' -AsPlainText -Force | Measure-PassForgeStrength
Check 'common password is weak' ($m.Strength -eq 'Weak')
$m = ConvertTo-SecureString $pw[0].Password -AsPlainText -Force | Measure-PassForgeStrength
Check 'generated password strong+' ($m.Strength -in 'Strong','Excellent')

try {
  $r = ConvertTo-SecureString 'password' -AsPlainText -Force | Test-PassForgePwned
  Check "pwned check flags 'password' (seen $($r.TimesSeen))" $r.Pwned
} catch { "SKIP pwned API not reachable from this sandbox: $($_.Exception.Message)" }
if ($ok) { 'ALL TESTS PASSED' } else { 'SOME TESTS FAILED'; exit 1 }
