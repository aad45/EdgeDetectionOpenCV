import UIKit
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var imageView = UIImageView()
    var captureSession: AVCaptureSession!
    var useShapeDetectionMode = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupImageView()
        setupToggleSwitch()
    }

    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo

        guard let backCamera = AVCaptureDevice.default(for: .video) else {
            print("Unable to access back camera!")
            return
        }

        do {
            try backCamera.lockForConfiguration()

            // Set the frame rate to 60fps if supported
            if let format = backCamera.formats.first(where: { format in
                let ranges = format.videoSupportedFrameRateRanges
                return ranges.contains { $0.maxFrameRate >= 60 }
            }) {
                backCamera.activeFormat = format
                backCamera.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 60)
                backCamera.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 60)
            } else {
                print("60fps not supported")
            }

            backCamera.unlockForConfiguration()

            let input = try AVCaptureDeviceInput(device: backCamera)
            captureSession.addInput(input)
        } catch let error {
            print("Error Unable to initialize back camera:  \(error.localizedDescription)")
            return
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(videoOutput)

        captureSession.startRunning()
    }

    func setupImageView() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func setupToggleSwitch() {
        let toggleSwitch = UISwitch()
        toggleSwitch.translatesAutoresizingMaskIntoConstraints = false
        toggleSwitch.addTarget(self, action: #selector(toggleMode), for: .valueChanged)
        view.addSubview(toggleSwitch)
        NSLayoutConstraint.activate([
            toggleSwitch.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            toggleSwitch.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc func toggleMode(_ sender: UISwitch) {
        useShapeDetectionMode = sender.isOn
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Assume portrait orientation for simplicity
        let orientedImage = ciImage.oriented(.right)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(orientedImage, from: orientedImage.extent) else { return }
        let image = UIImage(cgImage: cgImage)
        
        DispatchQueue.main.async {
            if self.useShapeDetectionMode {
                self.imageView.image = OpenCVWrapper.detectShapes(image)
            } else {
                if let result = OpenCVWrapper.detectShapes2(image) as? [String: Any],
                   let resultImage = result["image"] as? UIImage {
                    self.imageView.image = resultImage
                }
            }
        }
    }
}
