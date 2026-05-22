1. Verify that I see the GPU on the host
```
lspci | grep -i vga
```
Output:
04:00.0 VGA compatible controller: NVIDIA Corporation GK208B [GeForce GT 710] (rev a1)
2d:00.0 VGA compatible controller: Intel Corporation DG2 [Arc A380] (rev 05)

2. Enable IOMMU
```
nano /etc/default/grub
```
    a.  Change this line: 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' to 
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"
```

3. Update grub + reboot
```
update-grub
reboot
```

4. Pass through GPU to Ubuntu machine:
	1. dock-prod -> Hardware -> Add -> PCI Device -> Raw Device (Select Intel A380)
		1. Check 'all functions'
	2. Reboot + run this to verify it has been passed through:
```
	lspci | grep -i vga
```

