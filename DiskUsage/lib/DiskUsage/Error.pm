
package DiskUsage::Error;

use Exception::Class (
  "DiskUsage::Error",
  "DiskUsage::Errors" =>
    { isa => "DiskUsage::Error" },
  "DiskUsage::Errors::Recoverable" =>
    { isa => "DiskUsage::Error" },
  "DiskUsage::Errors::Fatal" =>
    { isa => "DiskUsage::Error" },
);

1;
