package dev.homeserver.ssdbridge

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NetworkAccessPolicyTest {
    @Test fun allowsLoopbackOnlyForLocalCleartext() {
        assertTrue(NetworkAccessPolicy.allowsCleartextPeer("127.0.0.1"))
        assertTrue(NetworkAccessPolicy.allowsCleartextPeer("::1"))
    }

    @Test fun allowsTailscaleIpv4AndIpv6Ranges() {
        assertTrue(NetworkAccessPolicy.allowsCleartextPeer("100.64.0.1"))
        assertTrue(NetworkAccessPolicy.allowsCleartextPeer("100.127.255.254"))
        assertTrue(NetworkAccessPolicy.allowsCleartextPeer("fd7a:115c:a1e0::1234"))
    }

    @Test fun rejectsLanPublicAndMalformedPeers() {
        assertFalse(NetworkAccessPolicy.allowsCleartextPeer("192.168.1.10"))
        assertFalse(NetworkAccessPolicy.allowsCleartextPeer("10.0.0.5"))
        assertFalse(NetworkAccessPolicy.allowsCleartextPeer("8.8.8.8"))
        assertFalse(NetworkAccessPolicy.allowsCleartextPeer("100.63.255.255"))
        assertFalse(NetworkAccessPolicy.allowsCleartextPeer("not-an-ip"))
        assertFalse(NetworkAccessPolicy.allowsCleartextPeer(null))
    }
}
