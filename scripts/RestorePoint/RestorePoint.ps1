$Config = @{
    Description = "Monthly Cleanup"
}

Checkpoint-Computer -Description $Config.Description
