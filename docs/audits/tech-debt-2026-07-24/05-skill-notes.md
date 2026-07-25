# Skill Notes

- The `refactor-opportunity-audit` skill emphasizes gathering evidence over making immediate code changes.
- The automated tools provided great initial signals, but false positives are common. For instance, string formatting in `PDSMigrationManager.m` is likely safe because the table names are static schema constants, not user input. However, in `PDSAdminService.m`, string formatting in the `IN` clause should be replaced with proper parameter binding.
- Timing-vulnerable comparisons were heavily flagged by the security scan (`isEqualToString:` instead of constant-time compares).
- Always verify the findings manually before scheduling the refactor in the roadmap.
