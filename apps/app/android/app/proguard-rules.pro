# junrar pulls slf4j-api without a concrete SLF4J binding; SLF4J falls back to NOP safely at runtime.
-dontwarn org.slf4j.impl.StaticLoggerBinder
-dontwarn org.slf4j.impl.StaticMDCBinder
-dontwarn org.slf4j.impl.StaticMarkerBinder
