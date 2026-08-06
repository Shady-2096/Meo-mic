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
                    .foregroundStyle(Palette.overlay)
            }
        }
        .frame(width: 148, height: 148)
        .padding(12)
        .background(Palette.text)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
