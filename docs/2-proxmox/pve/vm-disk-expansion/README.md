1. VM -> Hardware -> Select Hard Disk to expand -> Disk Action -> Resize
2. SSH/Console into VM and run this if disk is sda2. **lsblk** or **df -h** will show you. This will expand available space into the full disk
```
sudo growpart /dev/sda2 
```

3. Run this to resize the filesystem:
```
sudo resize2fs /dev/sda2
```
