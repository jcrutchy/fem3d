# Invalid-input regression corpus

These cases intentionally contain malformed or invalid model data. The regression runner checks that the CLI rejects them with the documented exit code and, where specified, the expected diagnostic code/text.

Add cases whenever a parser or validator bug is found. A previously crashing or silently accepted input should become a permanent regression case.
