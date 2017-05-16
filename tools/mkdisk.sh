#!/bin/sh

(
echo n # Add a new partition
echo e # extended
echo 1 # Partition number
echo   # First sector (Accept default: 1)
echo   # Last sector (Accept default: varies)

echo n # Add a new partition
echo l # Primary partition
echo   # First sector (Accept default: 1)
echo +125G  # Last sector (Accept default: varies)

echo n # Add a new partition
echo l # Primary partition
echo   # First sector (Accept default: 1)
echo +125G  # Last sector (Accept default: varies)

echo n # Add a new partition
echo l # Primary partition
echo   # First sector (Accept default: 1)
echo +125G  # Last sector (Accept default: varies)

echo n # Add a new partition
echo l # Primary partition
echo   # First sector (Accept default: 1)
echo +125G  # Last sector (Accept default: varies)

echo n # Add a new partition
echo l # Primary partition
echo   # First sector (Accept default: 1)
echo +125G  # Last sector (Accept default: varies)

echo n # Add a new partition
echo l # Primary partition
echo   # First sector (Accept default: 1)
echo +125G  # Last sector (Accept default: varies)

echo n # Add a new partition
echo l # Primary partition
echo   # First sector (Accept default: 1)
echo +125G  # Last sector (Accept default: varies)

echo n # Add a new partition
echo l # Primary partition
echo   # First sector (Accept default: 1)
echo +125G  # Last sector (Accept default: varies)

echo n # Add a new partition
echo l # Primary partition
echo   # First sector (Accept default: 1)
echo +125G  # Last sector (Accept default: varies)

echo n # Add a new partition
echo l # Primary partition
echo   # First sector (Accept default: 1)
echo +125G  # Last sector (Accept default: varies)

echo n # Add a new partition
echo l # Primary partition
echo   # First sector (Accept default: 1)
echo +125G  # Last sector (Accept default: varies)

echo n # Add a new partition
echo l # Primary partition
echo   # First sector (Accept default: 1)
echo +125G  # Last sector (Accept default: varies)

echo w # write changes

) | sudo fdisk /dev/nvme0n1
