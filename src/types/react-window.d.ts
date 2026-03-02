declare module 'react-window' {
  import * as React from 'react';

  export type ListChildComponentProps = {
    index: number;
    style: React.CSSProperties;
    data?: unknown;
    isScrolling?: boolean;
  };

  export type FixedSizeListProps = {
    height: number | string;
    width: number | string;
    itemCount: number;
    itemSize: number;
    overscanCount?: number;
    itemData?: unknown;
    className?: string;
    style?: React.CSSProperties;
    children: React.ComponentType<ListChildComponentProps> | ((props: ListChildComponentProps) => React.ReactNode);
  };

  export class FixedSizeList extends React.Component<FixedSizeListProps> {}
}
