String fulfillmentStatusLabel(String status) => switch (status) {
      'paid' => '결제완료',
      'preparing' => '상품준비',
      'shipped' => '발송',
      'delivered' => '배송완료',
      _ => status,
    };

String shippingOwnerLabel(String sellerType) =>
    sellerType == 'platform' ? '자사배송' : '판매자배송';

String? nextFulfillmentStatus(String current) => switch (current) {
      'paid' => 'preparing',
      'preparing' => 'shipped',
      'shipped' => 'delivered',
      _ => null,
    };

String nextFulfillmentActionLabel(String current) => switch (current) {
      'paid' => '준비',
      'preparing' => '발송',
      'shipped' => '배송완료',
      _ => '',
    };
