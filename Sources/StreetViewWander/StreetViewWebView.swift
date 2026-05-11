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
        webView.wantsLayer = true
        webView.layer?.isOpaque = true
        webView.layer?.drawsAsynchronously = true
        webView.setValue(true, forKey: "drawsBackground")
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
          #mapPanel {
            position: absolute;
            right: 16px;
            bottom: 16px;
            width: min(420px, calc(100vw - 32px));
            height: min(300px, 38vh);
            min-width: 240px;
            min-height: 180px;
            max-width: calc(100vw - 32px);
            max-height: calc(100vh - 96px);
            border: 1px solid rgba(255,255,255,.18);
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 16px 36px rgba(0,0,0,.28);
            background: #dfe6e1;
            display: none;
            contain: layout paint;
          }
          #mapPanel.is-collapsed {
            width: auto !important;
            height: 36px !important;
            min-width: 0;
            min-height: 0;
            max-width: none;
            max-height: none;
            overflow: visible;
            border-color: transparent;
            background: transparent;
            box-shadow: none;
            pointer-events: none;
          }
          #mapBody {
            position: absolute;
            inset: 0;
          }
          #mapPanel.is-collapsed #mapBody,
          #mapPanel.is-collapsed #mapResizeHandle {
            display: none;
          }
          #mapPanel.is-map-paused #mapBody {
            visibility: hidden;
          }
          #map {
            width: 100%;
            height: 100%;
          }
          #mapCenterPin {
            position: absolute;
            left: 50%;
            top: 50%;
            width: 14px;
            height: 14px;
            border: 3px solid #fff;
            border-radius: 50%;
            background: #176c5f;
            box-shadow: 0 2px 10px rgba(0,0,0,.35);
            transform: translate(-50%, -50%);
            pointer-events: none;
          }
          #mapToggle {
            position: absolute;
            top: 10px;
            right: 10px;
            z-index: 3;
            min-height: 36px;
            border: 0;
            border-radius: 8px;
            padding: 0 12px;
            color: #fff;
            background: rgba(13,18,17,.86);
            box-shadow: 0 10px 24px rgba(0,0,0,.26);
            font: inherit;
            font-size: 13px;
            font-weight: 800;
            cursor: pointer;
            pointer-events: auto;
          }
          #mapToggle:hover {
            background: rgba(13,18,17,.96);
          }
          #mapPanel.is-collapsed #mapToggle {
            top: auto;
            right: 0;
            bottom: 0;
          }
          #mapResizeHandle {
            position: absolute;
            left: -1px;
            top: -1px;
            z-index: 4;
            width: 22px;
            height: 22px;
            border: 0;
            border-right: 1px solid rgba(255,255,255,.22);
            border-bottom: 1px solid rgba(255,255,255,.22);
            border-radius: 8px 0 8px 0;
            background: rgba(13,18,17,.72);
            cursor: nwse-resize;
          }
          #mapResizeHandle::before {
            content: "";
            position: absolute;
            left: 7px;
            top: 7px;
            width: 8px;
            height: 8px;
            border-left: 2px solid rgba(255,255,255,.9);
            border-top: 2px solid rgba(255,255,255,.9);
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
            <aside id="mapPanel" aria-label="Floating map">
              <button id="mapResizeHandle" type="button" aria-label="Resize map"></button>
              <button id="mapToggle" type="button" aria-controls="mapBody" aria-expanded="true">Hide map</button>
              <div id="mapBody">
                <div id="map"></div>
                <div id="mapCenterPin" aria-hidden="true"></div>
              </div>
            </aside>
            <div id="empty">Street View will appear here.</div>
            <div id="error"></div>
          </div>
        <script>
          (() => {
            const streetviewElement = document.getElementById('streetview');
            const mapPanelElement = document.getElementById('mapPanel');
            const mapElement = document.getElementById('map');
            const mapBodyElement = document.getElementById('mapBody');
            const mapToggleElement = document.getElementById('mapToggle');
            const mapResizeHandleElement = document.getElementById('mapResizeHandle');
            const emptyElement = document.getElementById('empty');
            const errorElement = document.getElementById('error');

            const MIN_MAP_WIDTH = 240;
            const MIN_MAP_HEIGHT = 180;
            const MAP_MARGIN = 16;
            const MAP_ZOOM = 15;

            let mapsPromise = null;
            let loadedKey = null;
            let panorama = null;
            let map = null;
            let activeGoogle = null;
            let currentCenter = null;
            let isMapExpanded = true;
            let mapResizeFrame = 0;
            let mapPauseTimer = 0;
            let resizeDrag = null;

            function showError(message) {
              errorElement.textContent = message;
              errorElement.style.display = message ? 'block' : 'none';
            }

            function setEmpty(message) {
              emptyElement.textContent = message;
              emptyElement.style.display = message ? 'grid' : 'none';
              mapPanelElement.style.display = 'none';
            }

            function clamp(value, min, max) {
              return Math.min(Math.max(value, min), max);
            }

            function mapSizeBounds() {
              return {
                width: Math.max(MIN_MAP_WIDTH, window.innerWidth - MAP_MARGIN * 2),
                height: Math.max(MIN_MAP_HEIGHT, window.innerHeight - 96)
              };
            }

            function setMapPanelSize(width, height) {
              const bounds = mapSizeBounds();
              mapPanelElement.style.width = `${clamp(width, MIN_MAP_WIDTH, bounds.width)}px`;
              mapPanelElement.style.height = `${clamp(height, MIN_MAP_HEIGHT, bounds.height)}px`;
              requestMapResize();
            }

            function requestMapResize() {
              if (!map || mapResizeFrame) {
                return;
              }
              mapResizeFrame = requestAnimationFrame(() => {
                mapResizeFrame = 0;
                if (activeGoogle?.maps?.event?.trigger) {
                  activeGoogle.maps.event.trigger(map, 'resize');
                }
                if (currentCenter) {
                  map.setCenter(currentCenter);
                }
              });
            }

            function setMapExpanded(nextValue) {
              isMapExpanded = nextValue;
              mapPanelElement.classList.toggle('is-collapsed', !isMapExpanded);
              mapToggleElement.textContent = isMapExpanded ? 'Hide map' : 'Map';
              mapToggleElement.setAttribute('aria-expanded', String(isMapExpanded));
              mapBodyElement.setAttribute('aria-hidden', String(!isMapExpanded));
              if (isMapExpanded) {
                requestAnimationFrame(() => {
                  syncMapFromStreetView();
                  requestMapResize();
                });
              }
            }

            function pauseMapDuringStreetViewMove() {
              if (!isMapExpanded) {
                return;
              }
              mapPanelElement.classList.add('is-map-paused');
              window.clearTimeout(mapPauseTimer);
              mapPauseTimer = window.setTimeout(() => {
                mapPanelElement.classList.remove('is-map-paused');
                syncMapFromStreetView();
              }, 700);
            }

            function syncMap(center) {
              if (center) {
                currentCenter = center;
              }
              if (!activeGoogle || !center || !isMapExpanded) {
                return;
              }

              if (!map) {
                map = new activeGoogle.maps.Map(mapElement, {
                  center,
                  zoom: MAP_ZOOM,
                  mapTypeId: 'roadmap',
                  disableDefaultUI: true,
                  clickableIcons: false,
                  keyboardShortcuts: false,
                  scrollwheel: true,
                  gestureHandling: 'greedy'
                });
              } else {
                map.setCenter(center);
                map.setZoom(MAP_ZOOM);
              }
            }

            function syncMapFromStreetView() {
              if (!panorama?.getPosition) {
                syncMap(currentCenter);
                return;
              }
              const position = panorama.getPosition();
              if (!position) {
                syncMap(currentCenter);
                return;
              }
              syncMap({
                lat: position.lat(),
                lng: position.lng()
              });
            }

            function installStreetViewListeners() {
              panorama.addListener('pano_changed', pauseMapDuringStreetViewMove);
              panorama.addListener('position_changed', pauseMapDuringStreetViewMove);
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

            mapToggleElement.addEventListener('click', () => {
              setMapExpanded(!isMapExpanded);
            });

            mapResizeHandleElement.addEventListener('pointerdown', (event) => {
              if (!isMapExpanded) {
                return;
              }
              const rect = mapPanelElement.getBoundingClientRect();
              resizeDrag = {
                pointerId: event.pointerId,
                startX: event.clientX,
                startY: event.clientY,
                width: rect.width,
                height: rect.height
              };
              mapResizeHandleElement.setPointerCapture(event.pointerId);
              document.body.style.userSelect = 'none';
              event.preventDefault();
            });

            mapResizeHandleElement.addEventListener('pointermove', (event) => {
              if (!resizeDrag || resizeDrag.pointerId !== event.pointerId) {
                return;
              }
              const nextWidth = resizeDrag.width + resizeDrag.startX - event.clientX;
              const nextHeight = resizeDrag.height + resizeDrag.startY - event.clientY;
              setMapPanelSize(nextWidth, nextHeight);
              event.preventDefault();
            });

            function finishResize(event) {
              if (!resizeDrag || resizeDrag.pointerId !== event.pointerId) {
                return;
              }
              resizeDrag = null;
              document.body.style.userSelect = '';
              if (mapResizeHandleElement.hasPointerCapture(event.pointerId)) {
                mapResizeHandleElement.releasePointerCapture(event.pointerId);
              }
              requestMapResize();
            }

            mapResizeHandleElement.addEventListener('pointerup', finishResize);
            mapResizeHandleElement.addEventListener('pointercancel', finishResize);

            window.addEventListener('resize', () => {
              if (isMapExpanded && mapPanelElement.style.width && mapPanelElement.style.height) {
                const rect = mapPanelElement.getBoundingClientRect();
                setMapPanelSize(rect.width, rect.height);
              } else {
                requestMapResize();
              }
            });

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

                  activeGoogle = google;
                  currentCenter = center;
                  setEmpty('');
                  mapPanelElement.style.display = 'block';
                  setMapExpanded(isMapExpanded);

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
                    installStreetViewListeners();
                  } else {
                    panorama.setOptions({
                      pano: item.panoId,
                      pov,
                      zoom,
                      visible: true
                    });
                  }

                  syncMap(center);
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
