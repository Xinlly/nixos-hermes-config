# hosts/raiyun2/disk-config.nix — disko 分区布局（BIOS + GPT）
# 新机磁盘为 /dev/sda（SCSI sd 驱动，非雨云的 virtio vda）
# 参考: nix-community/disko example/gpt-bios-compat.nix
{ lib, ... }:
{
  disko.devices = {
    disk.main = {
      device = lib.mkDefault "/dev/sda";  # 可被外部覆盖
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
