import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeView: View {
    let payload: String

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .frame(width: 160, height: 160)
        .padding(14)
        // Always white, in both appearances: a scanner needs the contrast, and
        // a QR code that fails to read is not a design decision worth having.
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous)
                .strokeBorder(Palette.groupStroke, lineWidth: 1)
        }
    }

    private var image: NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let representation = NSCIImageRep(ciImage: transformed)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
