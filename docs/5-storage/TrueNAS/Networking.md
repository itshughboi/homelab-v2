### Bridge
Advantages: If you have a lot of containers attached to a bridge and you want to change out the interface, you just have to remap the bridge to the new physical interface

**System** -> **Network** -> **Interfaces**. You will see TrueNAS IP there
- Take note of the interface name
- 3 dots -> Edit and REMOVE the IP and hit **Save**. DO NOT HIT "TEST CHANGES"
- Add interface
	- Type: Bridge
	- Name: br0
	- IP: Put in same IP
	- Bridge Members: Name of original interface