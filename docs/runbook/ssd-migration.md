# Move everything to an external SSD (later)

Only `CYBERAI_ROOT` changes. Procedure (nothing destructive until the last step):
```
1. Stop all VMs:            ./cyberai list ; ./cyberai stop <each>
2. Back up first:           ./cyberai backup /media/$USER/HDD
3. Format+mount the SSD (ext4). Confirm the device with lsblk BEFORE mkfs.
4. Move registered VMs:     VBoxManage movevm CyberAI-Kali-Base   --type basic --folder /media/$USER/SSD/CyberAIKaliVM/images/base
                            VBoxManage movevm CyberAI-Kali-Golden --type basic --folder /media/$USER/SSD/CyberAIKaliVM/images/golden
5. rsync data dirs:         rsync -a downloads models rag /media/$USER/SSD/CyberAIKaliVM/
6. Edit .cyberai.env:       CYBERAI_ROOT="/media/$USER/SSD/CyberAIKaliVM"
7. Re-run:                  ./cyberai host-setup   (rebinds Ollama models path)
8. Verify:                  ./cyberai doctor
9. Only then delete the old copies.
```
Optional: symlink `~/Personal/CyberAIKaliVM -> /media/$USER/SSD/CyberAIKaliVM` so paths stay familiar.
