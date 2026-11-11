import Foundation
import Testing
@testable import Loge

struct HTTPRequestParserTests {
    @Test func waitsForHeadersAndBody() {
        #expect(HTTPRequestParser.parse(Data("GET / HTTP/1.1\r\nHost: x".utf8)) == .incomplete)
        let partialBody = "POST /add HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc"
        #expect(HTTPRequestParser.parse(Data(partialBody.utf8)) == .incomplete)
    }

    @Test func parsesCompleteRequest() throws {
        let raw = "POST /add HTTP/1.1\r\nContent-Length: 11\r\nCookie: a=1; session=tok\r\n\r\naddon_url=x"
        guard case .complete(let request) = HTTPRequestParser.parse(Data(raw.utf8)) else {
            Issue.record("expected complete request")
            return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/add")
        #expect(request.cookie("session") == "tok")
        #expect(request.formFields["addon_url"] == "x")
    }

    @Test func rejectsMalformedAndOversizedRequests() {
        #expect(HTTPRequestParser.parse(Data("NONSENSE\r\n\r\n".utf8)) == .invalid)
        #expect(HTTPRequestParser.parse(Data(count: HTTPRequestParser.maxRequestSize + 1)) == .invalid)
    }

    @Test func decodesFormEncoding() {
        let fields = HTTPRequestParser.formFields("addon_url=https%3A%2F%2Fa.b%2Fx+y&pin=1234")
        #expect(fields["addon_url"] == "https://a.b/x y")
        #expect(fields["pin"] == "1234")
    }

    @Test func escapesHTML() {
        #expect(HTTPRequestParser.htmlEscape(#"<script>alert("x")</script>&'"#)
            == "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;&amp;&#39;")
    }
}
