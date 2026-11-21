package io.github.augztn.pocketlink.ssdbridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NativeFileResponseOperationsTest {
    @Test
    fun parsesClosedOpenEndedAndSuffixRanges() {
        assertEquals(0L to 0L, parseByteRange("bytes=0-0", 10))
        assertEquals(4L to 9L, parseByteRange("bytes=4-", 10))
        assertEquals(6L to 9L, parseByteRange("bytes=-4", 10))
        assertEquals(0L to 9L, parseByteRange("bytes=-99", 10))
    }

    @Test
    fun clampsEndToFileLength() {
        assertEquals(2L to 9L, parseByteRange("bytes=2-99", 10))
    }

    @Test
    fun rejectsInvalidAndUnsatisfiableRanges() {
        assertNull(parseByteRange("bytes=10-10", 10))
        assertNull(parseByteRange("bytes=8-4", 10))
        assertNull(parseByteRange("bytes=-0", 10))
        assertNull(parseByteRange("bytes=-", 10))
        assertNull(parseByteRange("bytes=0-1,4-5", 10))
        assertNull(parseByteRange("bytes=999999999999999999999-", 10))
        assertNull(parseByteRange("bytes=0-0", 0))
    }
}
