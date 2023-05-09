//
//  ContentView.swift
//  Video Demo
//
//  Created by Peter Nash on 21/02/2023.
//

import SwiftUI
import QuickPoseCore
import QuickPoseSwiftUI

struct ContentView: View {
    
    indirect enum ViewState: Equatable {
        case notInitialized
        case introToApp
        case introToMeasurement(flexion: Bool)
        case loadingAfterThumbsUp(delaySeconds: Double, nextState: ViewState)
        case updateAndAddFeaturesAfterDelay(nextState: ViewState, delaySeconds: Double, features: [QuickPose.Feature])
        case measuring(flexion: Bool)
        case captureResult(flexion: Bool)
        case showResult(flexion: Bool)
        case completed
        
        func prompt(kneeLateralResult: QuickPose.FeatureResult?, kneeFlexionResult: QuickPose.FeatureResult?) -> String? {
            switch self {
            case .notInitialized, .updateAndAddFeaturesAfterDelay:
                return nil
            case .introToApp:
                return "This app measures your left knee's movements.\n\nWhen you are ready, give a thumbs up."
            case .loadingAfterThumbsUp:
                return "Awesome, continuing..."
            case .introToMeasurement:
                return "Please match the pose"
            case .measuring:
                return "Measuring"
            case .captureResult:
                return nil
            case .showResult(let flexion):
                if flexion {
                    return "Your flexion leg range of motion is\n\(kneeFlexionResult!.stringValue)\n\nThumbs up to continue, thumbs down to repeat."
                } else {
                    return "Your lateral leg range of motion is\n\(kneeLateralResult!.stringValue)\n\nThumbs up to continue, thumbs down to repeat."
                }
            case .completed:
                return "Measuring Complete\n\nLeft Leg Lateral\t\(kneeLateralResult!.stringValue)\nLeft Leg Flexion\t\(kneeFlexionResult!.stringValue)"
            }
        }
        
        var promptImage: String? {
            switch self {
            case .introToMeasurement(let flexion), .measuring(let flexion):
                return flexion ? "demo-flexion" : "demo-lateral"
            default:
                return nil
            }
        }
    }
    var quickPose = QuickPose(sdkKey: "01GSWNY1GK411GRZ0NJXBEYQA9")
    @State var overlayImage: UIImage?
    @State var viewState = ViewState.notInitialized
    @State var kneeLateralResult: QuickPose.FeatureResult?
    @State var kneeFlexionResult: QuickPose.FeatureResult?
    
    var unchangedDetector = QuickPoseDoubleUnchangedDetector(similarDuration: TimeInterval(0.3), leniency: 0.05)
    
    let kneeLateral = QuickPose.Feature.measureAngleBody(origin: .userRightKnee, p1: .userRightAnkle, p2: nil, clockwiseDirection: false)
    let kneeFlexion = QuickPose.Feature.rangeOfMotion(.knee(side: .right, clockwiseDirection: true))
    
    var body: some View {
        GeometryReader { reader in
            ZStack {
                if ProcessInfo.processInfo.isiOSAppOnMac, let url = Bundle.main.url(forResource: "user-v2", withExtension: "mov") {
                    QuickPoseSimulatedCameraView(useFrontCamera: true, delegate: quickPose, video: url) {
                        // on video loop
                        viewState = .updateAndAddFeaturesAfterDelay(nextState: .introToApp, delaySeconds: 2, features: [.thumbsUp()])
                    }
                } else {
                    QuickPoseCameraView(useFrontCamera: true, delegate: quickPose)
                }
                
                QuickPoseOverlayView(overlayImage: $overlayImage)
            }
            .overlay(alignment: .bottom) {
                if let prompt = viewState.prompt(kneeLateralResult: kneeLateralResult, kneeFlexionResult: kneeFlexionResult) {
                    Text(prompt)
                        .font(.system(size: 32))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 4).foregroundColor(Color.white))
                        .padding(.bottom, 100)
                        .multilineTextAlignment(.center)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let image = viewState.promptImage {
                    Image(image).resizable().aspectRatio(contentMode: .fit).frame(width: reader.size.width*0.3)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 4).foregroundColor(Color.white))
                        .padding(.bottom, 100)
                }
            }
            .onAppear {
                quickPose.start(features: []) { _, outputImage, results, _, _ in
                    overlayImage = outputImage
                    
                    if viewState == .introToApp, let measurementResult = results[.thumbsUp()] {
                        if measurementResult.value > 0.7 {
                            viewState = .loadingAfterThumbsUp(delaySeconds: 2.0, nextState: .introToMeasurement(flexion: false))
                        }
                    }
                    if case let .captureResult(flexion) = viewState, let measurementResult = results[flexion ? kneeFlexion : kneeLateral] {
                        
                        unchangedDetector.count(result: measurementResult.value) {
                            if flexion {
                                kneeFlexionResult = measurementResult
                            } else {
                                kneeLateralResult = measurementResult
                            }
                            
                            viewState = .updateAndAddFeaturesAfterDelay(nextState: .showResult(flexion: flexion), delaySeconds: 2, features: [.thumbsUpOrDown()])
                        }
                    }
                    
                    if case let .showResult(flexion) = viewState, let measurementResult = results[.thumbsUpOrDown()] {
                        
                        if measurementResult.value > 0.7 {
                            if measurementResult.stringValue == "thumbs_up" {
                                viewState = .loadingAfterThumbsUp(delaySeconds: 2.0, nextState: flexion ? .completed : .introToMeasurement(flexion: true))
                            } else if measurementResult.stringValue == "thumbs_down" {
                                viewState = .introToMeasurement(flexion: flexion)
                            }
                        }
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline:.now() + 2) {
                    viewState = .updateAndAddFeaturesAfterDelay(nextState: .introToApp, delaySeconds: 2, features: [.thumbsUp()])
                }
            }.onChange(of: viewState) { newViewState in
                if case let .introToMeasurement(flexion) = viewState {
                    quickPose.update(features: [flexion ? kneeFlexion : kneeLateral])
                    DispatchQueue.main.asyncAfter(deadline:.now() + 2) {
                        viewState = .measuring(flexion: flexion)
                        DispatchQueue.main.asyncAfter(deadline:.now() + 1) {
                            viewState = .captureResult(flexion: flexion)
                        }
                    }
                }
                
                if case .updateAndAddFeaturesAfterDelay(let nextState, let delay, let features) = newViewState {
                    viewState = nextState
                    quickPose.update(features: [])
                    DispatchQueue.main.asyncAfter(deadline:.now() + delay) {
                        quickPose.update(features: features)
                    }
                }
                
                if case .loadingAfterThumbsUp(let delay, let nextState) = viewState {
                    DispatchQueue.main.asyncAfter(deadline:.now() + delay) {
                        viewState = nextState
                    }
                }
            }
        }
    }
}
