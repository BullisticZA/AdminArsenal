@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Interactive wizards intentionally write coloured output for the operator.
        'PSAvoidUsingWriteHost'
    )
}
