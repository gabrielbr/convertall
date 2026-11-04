import XCTest
@testable import ConvertAllCore

final class MarkdownTests: XCTestCase {
    func testBlocks() {
        let md = """
        # Title

        A paragraph
        on two lines.

        - one
        - **two**

        1. first
        2. second

        > quoted *text*

        ```
        let x = 1 < 2
        ```

        ---
        ## Sub ##
        """
        let html = Markdown.blocks(md.components(separatedBy: "\n"))
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<p>A paragraph on two lines.</p>"))
        XCTAssertTrue(html.contains("<ul><li>one</li><li><strong>two</strong></li></ul>"))
        XCTAssertTrue(html.contains("<ol><li>first</li><li>second</li></ol>"))
        XCTAssertTrue(html.contains("<blockquote><p>quoted <em>text</em></p></blockquote>"))
        XCTAssertTrue(html.contains("<pre><code>let x = 1 &lt; 2</code></pre>"))
        XCTAssertTrue(html.contains("<hr>"))
        XCTAssertTrue(html.contains("<h2>Sub</h2>"))
    }

    func testInline() {
        XCTAssertEqual(Markdown.inline("**bold** and *it* and `a*b*c`"),
                       "<strong>bold</strong> and <em>it</em> and <code>a*b*c</code>")
        XCTAssertEqual(Markdown.inline("see [site](https://x.io) ![logo](l.png)"),
                       "see <a href=\"https://x.io\">site</a> <img alt=\"logo\" src=\"l.png\">")
        XCTAssertEqual(Markdown.inline("a < b & ~~old~~"), "a &lt; b &amp; <del>old</del>")
        XCTAssertEqual(Markdown.inline("2 * 3 * 4"), "2 * 3 * 4", "spaced asterisks aren't emphasis")
        XCTAssertTrue(Markdown.html(from: "hi", title: "T").contains("<title>T</title>"))
    }
}
