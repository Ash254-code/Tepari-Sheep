import Foundation

/// All transport implementations (TCP, BLE, Demo)
/// must deliver callbacks on the main thread.
protocol TransportProtocol: AnyObject {

    var isConnected: Bool { get }

    /// Raw line received from device (already framed by transport).
    /// Always delivered on main thread.
    var onReceiveLine: ((String) -> Void)? { get set }

    /// Connection state updates.
    /// Always delivered on main thread.
    var onStateChange: ((ConnectionState) -> Void)? { get set }

    func connect()
    func disconnect()
}
