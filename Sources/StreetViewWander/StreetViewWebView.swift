import StreetViewWanderCore
import SwiftUI
import WebKit

struct StreetViewWebView: NSViewRepresentable {
    var panorama: Panorama?
    var browserAPIKey: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.html, baseURL: URL(string: "http://127.0.0.1:5173/"))
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(
            panorama: panorama,
            browserAPIKey: browserAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    @MainActor
    final class Coordinator {
        weak var webView: WKWebView?
        private var lastSignature = ""
        private var pendingTask: Task<Void, Never>?

        func render(panorama: Panorama?, browserAPIKey: String) {
            let signature = "\(browserAPIKey)|\(panorama?.panoId ?? "none")|\(panorama?.heading ?? 0)"
            guard signature != lastSignature else {
                return
            }
            lastSignature = signature

            pendingTask?.cancel()
            pendingTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else {
                    return
                }
                guard let self, let webView = self.webView else {
                    return
                }

                let payload = WebPayload(apiKey: browserAPIKey, panorama: panorama)
                guard let data = try? JSONEncoder().encode(payload),
                      let json = String(data: data, encoding: .utf8) else {
                    return
                }

                _ = try? await webView.evaluateJavaScript("window.streetViewWander.render(\(json));")
            }
        }
    }

    private struct WebPayload: Encodable {
        var apiKey: String
        var panorama: Panorama?
    }

    private static let html = """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
          html, body, #stage {
            width: 100%;
            height: 100%;
            margin: 0;
            overflow: hidden;
            background: #dfe6e1;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          }
          #stage {
            position: relative;
          }
          #streetview {
            position: absolute;
            inset: 0;
          }
          #map {
            position: absolute;
            right: 16px;
            bottom: 16px;
            width: min(420px, calc(100vw - 32px));
            height: min(300px, 38vh);
            min-height: 220px;
            border: 1px solid rgba(255,255,255,.18);
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 16px 36px rgba(0,0,0,.28);
            background: #dfe6e1;
            display: none;
          }
          #empty {
            position: absolute;
            inset: 0;
            display: grid;
            place-items: center;
            color: #3f4745;
            font-size: 18px;
            font-weight: 700;
            text-align: center;
            padding: 24px;
          }
          #error {
            position: absolute;
            left: 50%;
            top: 82px;
            transform: translateX(-50%);
            max-width: min(680px, calc(100vw - 32px));
            padding: 12px 14px;
            border-radius: 8px;
            background: #ffe9e5;
            color: #6b2319;
            font-size: 13px;
            font-weight: 700;
            box-shadow: 0 16px 36px rgba(0,0,0,.22);
            display: none;
          }
        </style>
      </head>
      <body>
        <div id="stage">
          <div id="streetview"></div>
          <div id="map"></div>
          <div id="empty">Street View will appear here.</div>
          <div id="error"></div>
        </div>
        <script>
          (() => {
            const streetviewElement = document.getElementById('streetview');
            const mapElement = document.getElementById('map');
            const emptyElement = document.getElementById('empty');
            const errorElement = document.getElementById('error');

            let mapsPromise = null;
            let loadedKey = null;
            let panorama = null;
            let map = null;
            let marker = null;

            function showError(message) {
              errorElement.textContent = message;
              errorElement.style.display = message ? 'block' : 'none';
            }

            function setEmpty(message) {
              emptyElement.textContent = message;
              emptyElement.style.display = message ? 'grid' : 'none';
              mapElement.style.display = 'none';
            }

            function loadMaps(apiKey) {
              if (window.google?.maps?.StreetViewPanorama && loadedKey === apiKey) {
                return Promise.resolve(window.google);
              }
              if (mapsPromise && loadedKey === apiKey) {
                return mapsPromise;
              }

              loadedKey = apiKey;
              mapsPromise = new Promise((resolve, reject) => {
                document.querySelectorAll('script[data-streetview-wander]').forEach((node) => node.remove());
                const callbackName = `__streetViewWanderReady_${Date.now()}`;
                window[callbackName] = () => {
                  if (window.google?.maps?.StreetViewPanorama) {
                    resolve(window.google);
                  } else {
                    reject(new Error('Google Maps did not initialize.'));
                  }
                  delete window[callbackName];
                };

                const params = new URLSearchParams({
                  key: apiKey,
                  v: 'weekly',
                  loading: 'async',
                  callback: callbackName
                });
                const script = document.createElement('script');
                script.dataset.streetviewWander = 'true';
                script.async = true;
                script.defer = true;
                script.src = `https://maps.googleapis.com/maps/api/js?${params.toString()}`;
                script.onerror = () => reject(new Error('Could not load Google Maps.'));
                document.head.appendChild(script);
              });

              return mapsPromise;
            }

            function streetViewZoom(fov) {
              const zoom = Math.round(Math.log2(180 / fov));
              return Math.max(0, Math.min(4, zoom));
            }

            window.streetViewWander = {
              async render(payload) {
                showError('');
                if (!payload.apiKey) {
                  setEmpty('Add VITE_GOOGLE_MAPS_API_KEY in Settings.');
                  return;
                }
                if (!payload.panorama) {
                  setEmpty('Pick a random place to begin.');
                  return;
                }

                try {
                  const google = await loadMaps(payload.apiKey);
                  const item = payload.panorama;
                  const center = {
                    lat: item.location.lat,
                    lng: item.location.lng
                  };
                  const pov = {
                    heading: item.heading,
                    pitch: item.pitch
                  };
                  const zoom = streetViewZoom(item.fov);

                  setEmpty('');
                  mapElement.style.display = 'block';

                  if (!panorama) {
                    panorama = new google.maps.StreetViewPanorama(streetviewElement, {
                      pano: item.panoId,
                      pov,
                      zoom,
                      visible: true,
                      addressControl: true,
                      clickToGo: true,
                      enableCloseButton: false,
                      fullscreenControl: false,
                      linksControl: true,
                      motionTrackingControl: false,
                      panControl: false,
                      showRoadLabels: true,
                      zoomControl: false
                    });
                  } else {
                    panorama.setPano(item.panoId);
                    panorama.setPov(pov);
                    panorama.setZoom(zoom);
                    panorama.setVisible(true);
                  }

                  if (!map) {
                    map = new google.maps.Map(mapElement, {
                      center,
                      zoom: 6,
                      mapTypeId: 'roadmap',
                      disableDefaultUI: true,
                      clickableIcons: false,
                      keyboardShortcuts: false,
                      scrollwheel: true,
                      gestureHandling: 'greedy'
                    });
                  } else {
                    map.setCenter(center);
                    map.setZoom(6);
                  }

                  if (marker) {
                    marker.setMap(null);
                  }
                  marker = new google.maps.Marker({
                    position: center,
                    map
                  });
                } catch (error) {
                  showError(error instanceof Error ? error.message : 'Could not load Street View.');
                }
              }
            };
          })();
        </script>
      </body>
    </html>
    """
}
