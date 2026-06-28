# hosts/raiyun/disk-config.nix — disko 分区布局（BIOS + GPT）
# 参考: nix-community/disko example/gpt-bios-compat.nix
{
  disko.devices = {
    disk.main = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1M";
            type = "EF02";   # BIOS boot partition，存 GRUB core.img
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
