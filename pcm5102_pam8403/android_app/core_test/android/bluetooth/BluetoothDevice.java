package android.bluetooth;
import java.io.IOException;
import java.util.UUID;
/** JVM-only fake. Not included in the APK. */
public final class BluetoothDevice {
    private final BluetoothSocket socket;
    public BluetoothDevice(BluetoothSocket socket){this.socket=socket;}
    public BluetoothSocket createRfcommSocketToServiceRecord(UUID uuid)throws IOException{
        if(!uuid.toString().equals("00001101-0000-1000-8000-00805f9b34fb"))throw new IOException("Wrong SPP UUID");return socket;
    }
}
