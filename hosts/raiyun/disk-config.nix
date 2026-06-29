# hosts/raiyun/disk-config.nix — disko 分区布局（BIOS + GPT）
# 参考: nix-community/disko example/gpt-bios-compat.nix
# PARTLABEL 可靠（disko 自动生成 disk-main-root），fstab 用它跨内核设备名
{ lib, ... }:
{
  disko.devices = {
    disk.main = {
      device = lib.mkDefault "/dev/vda";  # 可被外部覆盖（KVM virtio 改名）
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1M";
            type = "EF02";          # BIOS boot partition
            attributes = [ 0 ];     # 官方示例必须—标记为 BIOS 兼容
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
