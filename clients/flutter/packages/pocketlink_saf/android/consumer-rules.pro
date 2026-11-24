# NewPipeExtractor's Rhino dependency references JavaBeans APIs that Android does not provide.
-dontwarn java.beans.**

# OkHttp detects these optional TLS providers at runtime; they are not bundled.
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
