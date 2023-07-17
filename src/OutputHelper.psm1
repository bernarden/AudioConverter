function Add-Timestamp { Process{"$(Get-Date -Format "s"): $_"} }

Export-ModuleMember -Function Add-Timestamp
