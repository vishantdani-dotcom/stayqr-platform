import { useEffect, useRef, useState } from "react";
import "./DocumentScanner.css";

const MAX_CAPTURE_DIMENSION = 3200;
const JPEG_QUALITY = 0.94;
const DEFAULT_CROP = Object.freeze({ top: 0, right: 0, bottom: 0, left: 0 });

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function assessFrame(context, width, height) {
  const sampleWidth = Math.min(width, 320);
  const sampleHeight = Math.max(1, Math.round((height / width) * sampleWidth));
  const canvas = document.createElement("canvas");
  canvas.width = sampleWidth;
  canvas.height = sampleHeight;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(context.canvas, 0, 0, sampleWidth, sampleHeight);
  const { data } = ctx.getImageData(0, 0, sampleWidth, sampleHeight);

  let brightness = 0;
  let edgeEnergy = 0;
  let previous = null;
  let clippedDark = 0;
  let clippedBright = 0;
  const pixels = data.length / 4;

  for (let index = 0; index < data.length; index += 4) {
    const luminance = 0.2126 * data[index] + 0.7152 * data[index + 1] + 0.0722 * data[index + 2];
    brightness += luminance;
    if (luminance < 22) clippedDark += 1;
    if (luminance > 244) clippedBright += 1;
    if (previous !== null) edgeEnergy += Math.abs(luminance - previous);
    previous = luminance;
  }

  const averageBrightness = brightness / Math.max(1, pixels);
  const averageEdgeEnergy = edgeEnergy / Math.max(1, pixels - 1);
  const darkRatio = clippedDark / Math.max(1, pixels);
  const brightRatio = clippedBright / Math.max(1, pixels);
  const flags = [];

  if (averageBrightness < 55) flags.push("too_dark");
  if (averageBrightness > 215) flags.push("too_bright");
  if (averageEdgeEnergy < 7) flags.push("possible_blur");
  if (brightRatio > 0.16) flags.push("possible_glare");
  if (darkRatio > 0.42) flags.push("heavy_shadow");

  let score = 100;
  score -= Math.min(35, Math.abs(130 - averageBrightness) * 0.28);
  if (averageEdgeEnergy < 12) score -= (12 - averageEdgeEnergy) * 3;
  score -= brightRatio * 80;
  score -= darkRatio * 50;
  score = Math.round(clamp(score, 0, 100));

  return {
    qualityStatus: flags.length === 0 && score >= 68 ? "pass" : "review",
    qualityScore: score,
    qualityFlags: flags,
  };
}

async function canvasToFile(canvas, fileName) {
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", JPEG_QUALITY));
  if (!blob) throw new Error("Unable to prepare the captured image.");
  return new File([blob], fileName, { type: "image/jpeg", lastModified: Date.now() });
}


function fitWithinMaximum(width, height) {
  const largest = Math.max(width, height);
  const scale = largest > MAX_CAPTURE_DIMENSION ? MAX_CAPTURE_DIMENSION / largest : 1;
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  };
}

async function blobToCanvas(blob) {
  if (!blob) return null;

  if (typeof window.createImageBitmap === "function") {
    const bitmap = await window.createImageBitmap(blob);
    try {
      const size = fitWithinMaximum(bitmap.width, bitmap.height);
      const canvas = document.createElement("canvas");
      canvas.width = size.width;
      canvas.height = size.height;
      const context = canvas.getContext("2d", { willReadFrequently: true });
      context.imageSmoothingEnabled = true;
      context.imageSmoothingQuality = "high";
      context.drawImage(bitmap, 0, 0, size.width, size.height);
      return canvas;
    } finally {
      bitmap.close?.();
    }
  }

  const objectUrl = URL.createObjectURL(blob);
  try {
    const image = new Image();
    image.decoding = "async";
    await new Promise((resolve, reject) => {
      image.onload = resolve;
      image.onerror = () => reject(new Error("Unable to decode the captured photo."));
      image.src = objectUrl;
    });
    const size = fitWithinMaximum(image.naturalWidth, image.naturalHeight);
    const canvas = document.createElement("canvas");
    canvas.width = size.width;
    canvas.height = size.height;
    const context = canvas.getContext("2d", { willReadFrequently: true });
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = "high";
    context.drawImage(image, 0, 0, size.width, size.height);
    return canvas;
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
}

async function tryHighResolutionStill(track) {
  if (!track || typeof window.ImageCapture !== "function") return null;

  try {
    const imageCapture = new window.ImageCapture(track);
    const blob = await imageCapture.takePhoto();
    const canvas = await blobToCanvas(blob);
    if (!canvas?.width || !canvas?.height) return null;
    return { canvas, method: "high_res_still" };
  } catch {
    return null;
  }
}

function cropCanvas(source, crop) {
  const top = clamp(Number(crop.top) || 0, 0, 35);
  const right = clamp(Number(crop.right) || 0, 0, 35);
  const bottom = clamp(Number(crop.bottom) || 0, 0, 35);
  const left = clamp(Number(crop.left) || 0, 0, 35);
  if (top + bottom >= 70 || left + right >= 70) {
    throw new Error("Crop margins are too large. Keep at least 30% of the document frame.");
  }

  const sx = Math.round(source.width * (left / 100));
  const sy = Math.round(source.height * (top / 100));
  const sw = Math.max(1, Math.round(source.width * (1 - (left + right) / 100)));
  const sh = Math.max(1, Math.round(source.height * (1 - (top + bottom) / 100)));
  const cropped = document.createElement("canvas");
  cropped.width = sw;
  cropped.height = sh;
  const context = cropped.getContext("2d", { willReadFrequently: true });
  context.drawImage(source, sx, sy, sw, sh, 0, 0, sw, sh);
  return cropped;
}

export default function DocumentScanner({ onCapture, disabled = false }) {
  const videoRef = useRef(null);
  const streamRef = useRef(null);
  const [open, setOpen] = useState(false);
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState("");
  const [preview, setPreview] = useState(null);
  const [rotation, setRotation] = useState(0);
  const [crop, setCrop] = useState(DEFAULT_CROP);
  const [cropCount, setCropCount] = useState(0);
  const [cameraReady, setCameraReady] = useState(false);
  const [streamVersion, setStreamVersion] = useState(0);
  const [capturing, setCapturing] = useState(false);
  const [cameraResolution, setCameraResolution] = useState("");
  const [torchSupported, setTorchSupported] = useState(false);
  const [torchOn, setTorchOn] = useState(false);
  const [zoomRange, setZoomRange] = useState(null);
  const [zoomValue, setZoomValue] = useState(null);
  const nativeCaptureRef = useRef(null);

  function stopCamera() {
    streamRef.current?.getTracks?.().forEach((track) => track.stop());
    streamRef.current = null;
    if (videoRef.current) videoRef.current.srcObject = null;
    setCameraReady(false);
    setCameraResolution("");
    setTorchSupported(false);
    setTorchOn(false);
    setZoomRange(null);
    setZoomValue(null);
  }

  useEffect(() => {
    return () => {
      streamRef.current?.getTracks?.().forEach((track) => track.stop());
      streamRef.current = null;
    };
  }, []);

  useEffect(() => {
    if (!open) return undefined;
    const onKeyDown = (event) => {
      if (event.key === "Escape") {
        streamRef.current?.getTracks?.().forEach((track) => track.stop());
        streamRef.current = null;
        setCameraReady(false);
        setOpen(false);
        setPreview(null);
        setRotation(0);
        setCrop(DEFAULT_CROP);
        setCropCount(0);
        setError("");
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [open]);

  useEffect(() => {
    if (!open || preview) return undefined;

    const video = videoRef.current;
    const stream = streamRef.current;
    if (!video || !stream) return undefined;

    let cancelled = false;

    async function attachStream() {
      try {
        if (video.srcObject !== stream) {
          video.srcObject = stream;
        }

        await video.play();

        if (cancelled) return;

        if (video.videoWidth > 0 && video.videoHeight > 0) {
          setCameraReady(true);
          setCameraResolution(`${video.videoWidth} × ${video.videoHeight}`);
          setError("");
          return;
        }

        const handleCanPlay = () => {
          if (cancelled) return;
          if (video.videoWidth > 0 && video.videoHeight > 0) {
            setCameraReady(true);
            setCameraResolution(`${video.videoWidth} × ${video.videoHeight}`);
            setError("");
          }
        };

        video.addEventListener("loadedmetadata", handleCanPlay, { once: true });
        video.addEventListener("canplay", handleCanPlay, { once: true });
      } catch (playError) {
        if (cancelled) return;
        setCameraReady(false);
        setError(playError.message || "Unable to start the camera preview.");
      }
    }

    attachStream();

    return () => {
      cancelled = true;
    };
  }, [open, preview, streamVersion]);

  async function startCamera() {
    if (disabled) return;
    setStarting(true);
    setCameraReady(false);
    setError("");
    setPreview(null);
    setRotation(0);
    setCrop(DEFAULT_CROP);
    setCropCount(0);

    try {
      if (!navigator.mediaDevices?.getUserMedia) {
        throw new Error("Camera capture is not supported by this browser.");
      }
      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: { ideal: "environment" },
          width: { ideal: 4096 },
          height: { ideal: 3072 },
          frameRate: { ideal: 30 },
        },
        audio: false,
      });
      stopCamera();
      streamRef.current = stream;

      const track = stream.getVideoTracks?.()[0];
      const capabilities = track?.getCapabilities?.() || {};
      const settings = track?.getSettings?.() || {};

      if (Array.isArray(capabilities.focusMode) && capabilities.focusMode.includes("continuous")) {
        try {
          await track.applyConstraints({ advanced: [{ focusMode: "continuous" }] });
        } catch {
          // Continuous autofocus is a best-effort enhancement.
        }
      }

      setTorchSupported(Boolean(capabilities.torch));
      if (Number.isFinite(capabilities.zoom?.min) && Number.isFinite(capabilities.zoom?.max)) {
        const min = Number(capabilities.zoom.min);
        const max = Number(capabilities.zoom.max);
        const step = Number(capabilities.zoom.step) || 0.1;
        const current = Number(settings.zoom);
        const initial = Number.isFinite(current) ? current : min;
        setZoomRange({ min, max, step });
        setZoomValue(initial);
      }

      setOpen(true);
      setStreamVersion((value) => value + 1);
    } catch (cameraError) {
      setCameraReady(false);
      setOpen(true);
      setError(cameraError.message || "Unable to access the camera.");
    } finally {
      setStarting(false);
    }
  }

  function closeScanner() {
    stopCamera();
    setOpen(false);
    setPreview(null);
    setRotation(0);
    setCrop(DEFAULT_CROP);
    setCropCount(0);
    setError("");
  }

  async function captureFrame() {
    const video = videoRef.current;
    const track = streamRef.current?.getVideoTracks?.()[0];

    if (!video?.videoWidth || !video?.videoHeight || !track) {
      setError("Camera frame is not ready yet.");
      return;
    }

    setCapturing(true);
    setError("");

    try {
      let captured = await tryHighResolutionStill(track);

      if (!captured) {
        const size = fitWithinMaximum(video.videoWidth, video.videoHeight);
        const canvas = document.createElement("canvas");
        canvas.width = size.width;
        canvas.height = size.height;
        const context = canvas.getContext("2d", { willReadFrequently: true });
        context.imageSmoothingEnabled = true;
        context.imageSmoothingQuality = "high";
        context.drawImage(video, 0, 0, size.width, size.height);
        captured = { canvas, method: "video_frame_fallback" };
      }

      const context = captured.canvas.getContext("2d", { willReadFrequently: true });
      const quality = assessFrame(context, captured.canvas.width, captured.canvas.height);

      setPreview({
        canvas: captured.canvas,
        quality,
        captureMethod: captured.method,
      });
      setCrop(DEFAULT_CROP);
      stopCamera();
    } catch (captureError) {
      setError(captureError.message || "Unable to capture this document.");
    } finally {
      setCapturing(false);
    }
  }

  async function toggleTorch() {
    const track = streamRef.current?.getVideoTracks?.()[0];
    if (!track || !torchSupported) return;

    const next = !torchOn;
    try {
      await track.applyConstraints({ advanced: [{ torch: next }] });
      setTorchOn(next);
      setError("");
    } catch {
      setError("Torch control is not available on this camera.");
    }
  }

  async function changeZoom(nextValue) {
    const track = streamRef.current?.getVideoTracks?.()[0];
    if (!track || !zoomRange) return;

    const next = clamp(Number(nextValue), zoomRange.min, zoomRange.max);
    try {
      await track.applyConstraints({ advanced: [{ zoom: next }] });
      setZoomValue(next);
      setError("");
    } catch {
      setError("Zoom control is not available on this camera.");
    }
  }

  async function useNativeCameraFile(event) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;

    setCapturing(true);
    setError("");

    try {
      const canvas = await blobToCanvas(file);
      if (!canvas?.width || !canvas?.height) {
        throw new Error("Unable to read the phone-camera image.");
      }
      const context = canvas.getContext("2d", { willReadFrequently: true });
      setPreview({
        canvas,
        quality: assessFrame(context, canvas.width, canvas.height),
        captureMethod: "native_camera_file",
      });
      setOpen(true);
      stopCamera();
    } catch (nativeError) {
      setError(nativeError.message || "Unable to use the phone camera image.");
      setOpen(true);
    } finally {
      setCapturing(false);
    }
  }

  function rotatePreview() {
    if (!preview?.canvas) return;
    const source = preview.canvas;
    const rotated = document.createElement("canvas");
    rotated.width = source.height;
    rotated.height = source.width;
    const context = rotated.getContext("2d", { willReadFrequently: true });
    context.translate(rotated.width / 2, rotated.height / 2);
    context.rotate(Math.PI / 2);
    context.drawImage(source, -source.width / 2, -source.height / 2);
    setPreview({ canvas: rotated, quality: assessFrame(context, rotated.width, rotated.height) });
    setRotation((value) => (value + 90) % 360);
    setCrop(DEFAULT_CROP);
  }

  function applyCrop() {
    if (!preview?.canvas) return;
    try {
      const cropped = cropCanvas(preview.canvas, crop);
      const context = cropped.getContext("2d", { willReadFrequently: true });
      setPreview({ canvas: cropped, quality: assessFrame(context, cropped.width, cropped.height) });
      setCrop(DEFAULT_CROP);
      setCropCount((value) => value + 1);
      setError("");
    } catch (cropError) {
      setError(cropError.message || "Unable to crop this capture.");
    }
  }

  async function useCapture() {
    if (!preview?.canvas) return;
    try {
      const file = await canvasToFile(preview.canvas, `guest-id-camera-${crypto.randomUUID()}.jpg`);
      onCapture?.({
        file,
        captureSource: "camera",
        qualityStatus: preview.quality.qualityStatus,
        qualityScore: preview.quality.qualityScore,
        qualityFlags: [
          ...preview.quality.qualityFlags,
          `capture_method_${preview.captureMethod || "unknown"}`,
          `resolution_${preview.canvas.width}x${preview.canvas.height}`,
        ],
        captureMethod: preview.captureMethod,
        resolution: `${preview.canvas.width}x${preview.canvas.height}`,
        rotation,
        cropApplied: cropCount > 0,
        cropOperations: cropCount,
      });
      closeScanner();
    } catch (captureError) {
      setError(captureError.message || "Unable to use the captured document.");
    }
  }

  return (
    <div className="document-scanner">
      <div className="document-scanner-launchers">
        <button type="button" className="secondary" onClick={startCamera} disabled={disabled || starting || capturing}>
          {starting ? "Starting camera…" : "Scan with camera"}
        </button>
        <button
          type="button"
          className="secondary"
          onClick={() => nativeCaptureRef.current?.click()}
          disabled={disabled || capturing}
          title="Uses the phone's native camera when available for maximum still-photo quality."
        >
          High-quality phone camera
        </button>
        <input
          ref={nativeCaptureRef}
          type="file"
          accept="image/*"
          capture="environment"
          className="document-native-capture-input"
          onChange={useNativeCameraFile}
          tabIndex="-1"
          aria-hidden="true"
        />
      </div>

      {open && (
        <div className="document-scanner-modal" role="dialog" aria-modal="true" aria-label="Document camera scanner">
          <div className="document-scanner-card">
            <div className="document-scanner-head">
              <div>
                <p className="guest-directory-kicker">PRIVATE ID CAPTURE</p>
                <h3>Document scanner</h3>
                <p>Capture only the ID document. StayQR does not perform face recognition or biometric matching.</p>
              </div>
              <button type="button" className="secondary" onClick={closeScanner}>Close</button>
            </div>

            {error && <div className="document-scanner-error" role="alert">{error}</div>}

            {!preview ? (
              <div className="document-scanner-stage">
                <video ref={videoRef} playsInline muted aria-label="Live document camera preview" />
                <div className="document-scanner-frame" aria-hidden="true" />

                <div className="document-camera-status">
                  <span>{cameraResolution ? `Live ${cameraResolution}` : "Preparing camera…"}</span>
                  <span>High-resolution still preferred</span>
                </div>

                {(torchSupported || zoomRange) && (
                  <div className="document-camera-controls">
                    {torchSupported && (
                      <button type="button" className="secondary" onClick={toggleTorch}>
                        {torchOn ? "Turn torch off" : "Turn torch on"}
                      </button>
                    )}

                    {zoomRange && (
                      <label>
                        <span>Zoom {Number(zoomValue || zoomRange.min).toFixed(1)}×</span>
                        <input
                          type="range"
                          min={zoomRange.min}
                          max={zoomRange.max}
                          step={zoomRange.step}
                          value={zoomValue ?? zoomRange.min}
                          onChange={(event) => changeZoom(event.target.value)}
                        />
                      </label>
                    )}
                  </div>
                )}

                <p>Fill the frame with the document, hold steady, avoid glare, and use the rear camera where possible.</p>
                <button type="button" onClick={captureFrame} disabled={!cameraReady || capturing}>
                  {capturing ? "Capturing high-resolution photo…" : "Capture document"}
                </button>
              </div>
            ) : (
              <div className="document-scanner-stage">
                <canvas
                  ref={(node) => {
                    if (!node || !preview.canvas) return;
                    node.width = preview.canvas.width;
                    node.height = preview.canvas.height;
                    node.getContext("2d").drawImage(preview.canvas, 0, 0);
                  }}
                  aria-label="Captured document preview"
                />
                <div className={`document-quality ${preview.quality.qualityStatus}`}>
                  <strong>{preview.quality.qualityStatus === "pass" ? "Quality check passed" : "Manual review recommended"}</strong>
                  <span>Score {preview.quality.qualityScore}/100</span>
                  <span>
                    {preview.captureMethod === "high_res_still"
                      ? "High-resolution still"
                      : preview.captureMethod === "native_camera_file"
                        ? "Native phone camera"
                        : "High-quality video frame"}
                    {" · "}{preview.canvas.width}×{preview.canvas.height}
                  </span>
                  {preview.quality.qualityFlags.length > 0 && (
                    <span>{preview.quality.qualityFlags.map((flag) => flag.replaceAll("_", " ")).join(" · ")}</span>
                  )}
                </div>

                <fieldset className="document-crop-controls">
                  <legend>Crop document edges</legend>
                  <p>Trim background around the document before saving. Values are percentages of the current image.</p>
                  <div className="document-crop-grid">
                    {[
                      ["top", "Top"],
                      ["right", "Right"],
                      ["bottom", "Bottom"],
                      ["left", "Left"],
                    ].map(([key, label]) => (
                      <label key={key}>
                        <span>{label}: {crop[key]}%</span>
                        <input
                          type="range"
                          min="0"
                          max="25"
                          step="1"
                          value={crop[key]}
                          onChange={(event) => setCrop((current) => ({ ...current, [key]: Number(event.target.value) }))}
                        />
                      </label>
                    ))}
                  </div>
                  <button
                    type="button"
                    className="secondary"
                    onClick={applyCrop}
                    disabled={Object.values(crop).every((value) => Number(value) === 0)}
                  >
                    Apply crop
                  </button>
                  {cropCount > 0 && <small>{cropCount} crop operation(s) applied.</small>}
                </fieldset>

                <div className="document-scanner-actions">
                  <button type="button" className="secondary" onClick={startCamera}>Retake</button>
                  <button type="button" className="secondary" onClick={rotatePreview}>Rotate 90°</button>
                  <button type="button" onClick={useCapture}>Use capture</button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
