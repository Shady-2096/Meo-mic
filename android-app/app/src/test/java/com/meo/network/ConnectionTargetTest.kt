package com.meo.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ConnectionTargetTest {

    @Test
    fun `parses the payload the desktop apps put in their QR code`() {
        assertEquals(
            ConnectionTarget("192.168.1.5", 48888),
            ConnectionTarget.parse("meomic://192.168.1.5:48888")
        )
    }

    @Test
    fun `falls back to the default port`() {
        assertEquals(
            ConnectionTarget("192.168.1.5", UdpAudioStreamer.DEFAULT_PORT),
            ConnectionTarget.parse("meomic://192.168.1.5")
        )
        assertEquals(
            ConnectionTarget("192.168.1.5", UdpAudioStreamer.DEFAULT_PORT),
            ConnectionTarget.parse("192.168.1.5")
        )
    }

    @Test
    fun `accepts typed addresses, hostnames and stray whitespace`() {
        assertEquals(
            ConnectionTarget("192.168.1.5", 5000),
            ConnectionTarget.parse("  192.168.1.5:5000  ")
        )
        assertEquals(
            ConnectionTarget("my-pc.local", 48888),
            ConnectionTarget.parse("MEOMIC://my-pc.local:48888/")
        )
    }

    @Test
    fun `rejects QR codes that are not Meo Mic addresses`() {
        assertNull(ConnectionTarget.parse(null))
        assertNull(ConnectionTarget.parse(""))
        assertNull(ConnectionTarget.parse("   "))
        assertNull(ConnectionTarget.parse("https://example.com"))
        assertNull(ConnectionTarget.parse("WIFI:S:home;T:WPA;P:hunter2;;"))
        assertNull(ConnectionTarget.parse("meomic://192.168.1.5/stream"))
        assertNull(ConnectionTarget.parse("meomic://"))
    }

    @Test
    fun `rejects unusable ports`() {
        assertNull(ConnectionTarget.parse("192.168.1.5:0"))
        assertNull(ConnectionTarget.parse("192.168.1.5:70000"))
        assertNull(ConnectionTarget.parse("192.168.1.5:port"))
        assertNull(ConnectionTarget.parse("192.168.1.5:"))
    }

    @Test
    fun `rejects IPv6 literals rather than failing later in the streamer`() {
        assertNull(ConnectionTarget.parse("meomic://[fe80::1]:48888"))
    }
}
