import CoreGraphics
import Foundation

private typealias Scan = PDFContentScan

/// A painted graphic found while interpreting a page content stream.
struct GraphicPiece {
    enum Kind { case image, vector }
    var kind: Kind
    var rect: CGRect
    var curves = 0
    var slanted = 0
    var barHeights: [Int] = []
}

/// Interprets a page's content stream and records painted graphics.
final class PDFContentScan {

    private(set) var pieces: [GraphicPiece] = []

    private var ctm = CGAffineTransform.identity
    private var stack: [CGAffineTransform] = []

    private var pathBounds: CGRect?
    private var current: CGPoint?
    private var segments = 0
    private var curves = 0
    private var slanted = 0
    private var rects: [CGRect] = []

    private var table: CGPDFOperatorTableRef?
    private var depth = 0

    func run(page: CGPDFPage) {
        guard let table = makeTable() else { return }
        self.table = table
        let stream = CGPDFContentStreamCreateWithPage(page)
        scan(stream)
        CGPDFContentStreamRelease(stream)
        CGPDFOperatorTableRelease(table)
        self.table = nil
    }

    private func scan(_ stream: CGPDFContentStreamRef) {
        guard let table else { return }
        let info = Unmanaged.passUnretained(self).toOpaque()
        let scanner = CGPDFScannerCreate(stream, table, info)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
    }

    // MARK: - Operator table

    private static func instance(_ info: UnsafeMutableRawPointer?) -> PDFContentScan? {
        info.map { Unmanaged<PDFContentScan>.fromOpaque($0).takeUnretainedValue() }
    }

    private static func numbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [CGFloat]? {
        var values = [CGFloat](repeating: 0, count: count)
        for index in stride(from: count - 1, through: 0, by: -1) {
            var value: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &value) else { return nil }
            values[index] = value
        }
        return values
    }

    private func makeTable() -> CGPDFOperatorTableRef? {
        guard let table = CGPDFOperatorTableCreate() else { return nil }
        registerStateOperators(in: table)
        registerPathOperators(in: table)
        registerPaintOperators(in: table)
        return table
    }

    private func registerStateOperators(in table: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            guard let scan = Scan.instance(info) else { return }
            scan.stack.append(scan.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            guard let scan = Scan.instance(info), let last = scan.stack.popLast() else { return }
            scan.ctm = last
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let scan = Scan.instance(info), let values = Scan.numbers(scanner, 6) else { return }
            scan.ctm = Scan.matrix(values).concatenating(scan.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            var name: UnsafePointer<CChar>?
            guard let scan = Scan.instance(info),
                  CGPDFScannerPopName(scanner, &name), let name else { return }
            scan.draw(xObject: name, scanner: scanner)
        }
    }

    private func registerPathOperators(in table: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
            guard let scan = Scan.instance(info), let values = Scan.numbers(scanner, 2) else { return }
            let point = CGPoint(x: values[0], y: values[1]).applying(scan.ctm)
            scan.current = point
            scan.include(point)
        }
        CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
            guard let scan = Scan.instance(info), let values = Scan.numbers(scanner, 2) else { return }
            let point = CGPoint(x: values[0], y: values[1]).applying(scan.ctm)
            if let from = scan.current, abs(point.x - from.x) > 1, abs(point.y - from.y) > 1 {
                scan.slanted += 1
            }
            scan.segments += 1
            scan.current = point
            scan.include(point)
        }
        CGPDFOperatorTableSetCallback(table, "c") { scanner, info in
            guard let scan = Scan.instance(info), let values = Scan.numbers(scanner, 6) else { return }
            scan.addCurve(through: values)
        }
        for name in ["v", "y"] {
            CGPDFOperatorTableSetCallback(table, name) { scanner, info in
                guard let scan = Scan.instance(info), let values = Scan.numbers(scanner, 4) else { return }
                scan.addCurve(through: values)
            }
        }
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            guard let scan = Scan.instance(info), let values = Scan.numbers(scanner, 4) else { return }
            let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
                .applying(scan.ctm).standardized
            scan.include(rect.origin)
            scan.include(CGPoint(x: rect.maxX, y: rect.maxY))
            scan.rects.append(rect)
        }
    }

    private func registerPaintOperators(in table: CGPDFOperatorTableRef) {
        for name in ["f", "F", "f*", "B", "B*", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, name) { _, info in
                Scan.instance(info)?.paint(fill: true)
            }
        }
        for name in ["S", "s"] {
            CGPDFOperatorTableSetCallback(table, name) { _, info in
                Scan.instance(info)?.paint(fill: false)
            }
        }
        CGPDFOperatorTableSetCallback(table, "n") { _, info in
            Scan.instance(info)?.resetPath()
        }
    }

    private static func matrix(_ values: [CGFloat]) -> CGAffineTransform {
        CGAffineTransform(
            a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5]
        )
    }

    // MARK: - Path handling

    /// Adds a Bézier segment whose operands are control and end points.
    private func addCurve(through values: [CGFloat]) {
        for index in stride(from: 0, to: values.count, by: 2) {
            include(CGPoint(x: values[index], y: values[index + 1]).applying(ctm))
        }
        curves += 1
        segments += 1
        let last = values.count - 2
        current = CGPoint(x: values[last], y: values[last + 1]).applying(ctm)
    }

    private func include(_ point: CGPoint) {
        let box = CGRect(origin: point, size: .zero)
        pathBounds = pathBounds.map { $0.union(box) } ?? box
    }

    private func resetPath() {
        pathBounds = nil
        current = nil
        segments = 0
        curves = 0
        slanted = 0
        rects.removeAll(keepingCapacity: true)
    }

    private func paint(fill: Bool) {
        defer { resetPath() }
        guard let bounds = pathBounds else { return }

        var piece = GraphicPiece(kind: .vector, rect: bounds)
        piece.curves = curves
        piece.slanted = slanted

        if fill, segments == 0 {
            piece.barHeights = rects
                .filter { $0.width > 2 && $0.height > 2 }
                .map { Int($0.height.rounded()) }
        }

        // Hairlines (rules, table borders) are not drawings by themselves.
        let thin = bounds.width < 1.5 || bounds.height < 1.5
        if thin && piece.slanted == 0 && piece.curves == 0 { return }

        pieces.append(piece)
    }

    // MARK: - XObjects

    private func draw(xObject name: UnsafePointer<CChar>, scanner: CGPDFScannerRef) {
        let contentStream = CGPDFScannerGetContentStream(scanner)
        guard let object = CGPDFContentStreamGetResource(contentStream, "XObject", name) else { return }

        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
              let dictionary = CGPDFStreamGetDictionary(stream) else { return }

        var subtype: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }

        switch String(cString: subtype) {
        case "Image":
            let rect = CGRect(x: 0, y: 0, width: 1, height: 1).applying(ctm).standardized
            pieces.append(GraphicPiece(kind: .image, rect: rect))
        case "Form":
            drawForm(stream: stream, dictionary: dictionary, parent: contentStream)
        default:
            break
        }
    }

    private func drawForm(
        stream: CGPDFStreamRef,
        dictionary: CGPDFDictionaryRef,
        parent: CGPDFContentStreamRef
    ) {
        guard depth < 4 else { return }
        depth += 1
        let savedCTM = ctm
        let savedStack = stack
        defer {
            depth -= 1
            ctm = savedCTM
            stack = savedStack
        }

        var matrixArray: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dictionary, "Matrix", &matrixArray),
           let matrixArray,
           let values = Scan.numbers(in: matrixArray, count: 6) {
            ctm = Scan.matrix(values).concatenating(ctm)
        }

        var resources: CGPDFDictionaryRef?
        CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)

        let formStream = CGPDFContentStreamCreateWithStream(stream, resources ?? dictionary, parent)
        scan(formStream)
        CGPDFContentStreamRelease(formStream)
    }

    private static func numbers(in array: CGPDFArrayRef, count: Int) -> [CGFloat]? {
        guard CGPDFArrayGetCount(array) >= count else { return nil }
        var values: [CGFloat] = []
        for index in 0..<count {
            var value: CGPDFReal = 0
            guard CGPDFArrayGetNumber(array, index, &value) else { return nil }
            values.append(value)
        }
        return values
    }
}
